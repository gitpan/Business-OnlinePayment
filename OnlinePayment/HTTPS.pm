package Business::OnlinePayment::HTTPS;

use strict;
use vars qw($VERSION @ISA $DEBUG $ssl_module $skip_NetSSLeay);
#use URI;
#use URI::QueryParam;
use URI::Escape;
use Tie::IxHash;

@ISA = qw( Business::OnlinePayment );

$VERSION = '0.03';

$DEBUG = 0;

BEGIN {

        $ssl_module = '';

        eval {
                die if defined($skip_NetSSLeay) && $skip_NetSSLeay;
                require Net::SSLeay;
                #import Net::SSLeay
                #  qw(get_https post_https make_form make_headers);
                $ssl_module = 'Net::SSLeay';
        };

        if ($@) {
                eval {
                        require LWP::UserAgent;
                        require HTTP::Request::Common;
                        require Crypt::SSLeay;
                        #import HTTP::Request::Common qw(GET POST);
                        $ssl_module = 'Crypt::SSLeay';
                };
        }

        unless ( $ssl_module ) {
                die "Net::SSLeay or Crypt::SSLeay (+LWP) is required";
        }

}

=head1 NAME

Business::OnlinePayment::HTTPS - Base class for HTTPS payment APIs

=head1 SYNOPSIS

  package Business::OnlinePayment::MyProcessor
  @ISA = qw( Business::OnlinePayment::HTTPS );

  sub submit {
          my $self = shift;

          #...

          # pass a list (order is preserved, if your gateway needs that)
          ($page, $response, %reply_headers)
            = $self->https_get( field => 'value', ... );

          #or a hashref
          my %hash = ( field => 'value', ... );
          ($page, $response_code, %reply_headers)
            = $self->https_get( $hashref );

          #...
  }

=head1 DESCRIPTION

This is a base class for HTTPS based gateways, providing useful code for
implementors of HTTPS payment APIs.

It depends on Net::SSLeay _or_ ( Crypt::SSLeay and LWP::UserAgent ).

=head1 METHODS

=over 4

=item https_get HASHREF | FIELD => VALUE, ...

Accepts parameters as either a hashref or a list of fields and values.  In the
latter case, ordering is preserved (see L<Tie::IxHash> to do so when passing a
hashref).

Returns a list consisting of the page content as a string, the HTTP response
code, and a list of key/value pairs representing the HTTP response headers.

=cut

sub https_get {
  my $self = shift;

  #accept a hashref or a list (keep it ordered)
  my $post_data;
  if ( ref($_[0]) ) {
    $post_data = shift;
  } else {
    tie my %hash, 'Tie::IxHash', @_;
    $post_data = \%hash;
  }

  my $path = $self->path;
  if ( keys %$post_data ) {

    #my $u = URI->new("", "https");
    #$u->query_param(%$post_data);
    #$path .= '?'. $u->query;

    $path .= '?'. join('&',
      map { uri_escape($_).'='. uri_escape($post_data->{$_}) }
      keys %$post_data
    );
    #warn $path;

  }

  my $referer = ''; ### XXX referer!!!
  my %headers;
  $headers{'Referer'} = $referer if length($referer);

  if ( $ssl_module eq 'Net::SSLeay' ) {

    import Net::SSLeay qw(get_https make_headers);
    my $headers = make_headers(%headers);
    get_https( $self->server, $self->port, $path, $referer, $headers );

  } elsif ( $ssl_module eq 'Crypt::SSLeay' ) {

    import HTTP::Request::Common qw(GET);

    my $url = 'https://'. $self->server;
    $url .= ':'. $self->port
      unless $self->port == 443;
    $url .= "/$path";

    my $ua = new LWP::UserAgent;
    my $res = $ua->request( GET( $url ) );

    #( $res->as_string, # wtf?
    ( $res->content,
      $res->code,
      map { $_ => $res->header($_) } $res->header_field_names
    );

  } else {

    die "unknown SSL module $ssl_module";

  }

}

=item https_post SCALAR | HASHREF | FIELD => VALUE, ...

Accepts form fields and values as either a hashref or a list.  In the latter
case, ordering is preserved (see L<Tie::IxHash> to do so when passing a
hashref).

Also accepts instead a simple scalar containing the raw content.

Returns a list consisting of the page content as a string, the HTTP response
code, and a list of key/value pairs representing the HTTP response headers.

=cut

sub https_post {
  my $self = shift;

  #accept a hashref or a list (keep it ordered)
  my $post_data;
  if ( ref($_[0]) eq 'HASH' ) {
    $post_data = shift;
  } elsif ( scalar(@_) > 1 ) {
    tie my %hash, 'Tie::IxHash', @_;
    $post_data = \%hash;
  } elsif ( scalar(@_) == 1 ) {
    $post_data = shift;
  } else {
    die "https_post called with no params\n";
  }

  my $referer = ''; ### XXX referer!!!
  my %headers;
  $headers{'Referer'} = $referer if length($referer);
  $headers{'Host'} = $self->server;

  if ( $DEBUG && ref($post_data) ) {
    warn join('', map { "  $_ => ". $post_data->{$_}. "\n" } keys %$post_data );
  }

  if ( $ssl_module eq 'Net::SSLeay' ) {

    #import Net::SSLeay qw(post_https make_headers make_form);
    import Net::SSLeay qw(make_headers make_form);
    my $headers = make_headers(%headers);

    if ( $DEBUG ) {
      warn $self->server. ':'. $self->port. $self->path. "\n";
      $Net::SSLeay::trace = 2;
    }
    #post_https( $self->server, $self->port, $self->path,
    #            $headers, make_form(%$post_data)  );

    my $raw_data = ref($post_data) ? make_form(%$post_data) : $post_data;
    _my_post_https( $self->server, $self->port, $self->path,
                    $headers, $raw_data );

  } elsif ( $ssl_module eq 'Crypt::SSLeay' ) {

    import HTTP::Request::Common qw(POST);

    my $url = 'https://'. $self->server;
    $url .= ':'. $self->port
      unless $self->port == 443;
    $url .= $self->path;

    if ( $DEBUG ) {
      warn $url;
    }

    my $ua = new LWP::UserAgent;

    my $res;
    if ( ref($post_data) ) {
      $res = $ua->request( POST( $url, [ %$post_data ] ) );
    } else {
      my $req =new HTTP::Request( 'POST' => $url );
      $req->content_type('application/x-www-form-urlencoded');
      $req->content($post_data);
      $res = $ua->request($req);
    }

    #( $res->as_string, # wtf?
    ( $res->content,
      $res->code,
      map { $_ => $res->header($_) } $res->header_field_names
    );

  } else {

    die "unknown SSL module $ssl_module";

  }

}

# SecureHostingUPG (and presumably other IIS-based gateways?) doesn't like the
# Host: $site:$port header auto-added by Net::SSLeay, which it adds regardless
# if you supply one or not

sub _my_post_https ($$$;***) { _my_do_httpx2(POST => 1, @_) }

sub _my_do_httpx2 {
    my ($page, $response, $headers, $server_cert) = &_my_do_httpx3;
    Net::SSLeay::X509_free($server_cert) if defined $server_cert;
    my($h,$v);
    return ($page, $response,
	    map( { ($h,$v)=/^(\S+)\:\s*(.*)$/; (uc($h),$v); }
		split(/\s?\n/, $headers)
		)
	    );
}

sub _my_do_httpx3 {
    my ($method, $usessl, $site, $port, $path, $headers,
	$content, $mime_type, $crt_path, $key_path) = @_;
    my ($response, $page, $h,$v);

    my $CRLF = $Net::SSLeay::CRLF;

    if ($content) {
	$mime_type = "application/x-www-form-urlencoded" unless $mime_type;
	my $len = Net::SSLeay::blength($content);
	$content = "Content-Type: $mime_type$CRLF"
	    . "Content-Length: $len$CRLF$CRLF$content";
    } else {
	$content = "$CRLF$CRLF";
    }

    my $req = "$method $path HTTP/1.0$CRLF";
    unless ( defined $headers && $headers =~ /^Host:/m ) {
      $req .= "Host: $site";
      unless ( ( $port==80 && !$usessl ) || ( $port==443 && $usessl ) ) {
        $req .= ":$port";
      }
      $req .= $CRLF;
    }
    $req .= (defined $headers ? $headers : '') . "Accept: */*$CRLF$content";    

    warn "do_httpx3($method,$usessl,$site:$port)" if $Net::SSLeay::trace;
    my ($http, $errs, $server_cert)
	= Net::SSLeay::httpx_cat($usessl, $site, $port, $req, $crt_path, $key_path);
    return (undef, "HTTP/1.0 900 NET OR SSL ERROR$CRLF$CRLF$errs") if $errs;
    
    $http = '' if !defined $http;
    ($headers, $page) = split /\s?\n\s?\n/, $http, 2;
    warn "headers >$headers< page >>$page<< http >>>$http<<<" if $Net::SSLeay::trace>1;
    ($response, $headers) = split /\s?\n/, $headers, 2;
    return ($page, $response, $headers, $server_cert);
}

=back

=head1 SEE ALSO 

L<Business::OnlinePayment>

=cut

1;

