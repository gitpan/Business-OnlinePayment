package Business::OnlinePayment::HTTPS;

use strict;
use vars qw($VERSION $DEBUG $ssl_module $skip_NetSSLeay);
use URI::Escape;
use Tie::IxHash;
use base qw(Business::OnlinePayment);

$VERSION = '0.09';
$DEBUG   = 0;

BEGIN {

    $ssl_module = '';

    eval {
        die if defined($skip_NetSSLeay) && $skip_NetSSLeay;
        require Net::SSLeay;
        Net::SSLeay->VERSION(1.30);

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

    unless ($ssl_module) {
        die "One of Net::SSLeay (v1.30 or later)"
          . " or Crypt::SSLeay (+LWP) is required";
    }

}

=head1 NAME

Business::OnlinePayment::HTTPS - Base class for HTTPS payment APIs

=head1 SYNOPSIS

  package Business::OnlinePayment::MyProcessor;
  use base qw(Business::OnlinePayment::HTTPS);
  
  sub submit {
      my $self = shift;
  
      #...
  
      # pass a list (order is preserved, if your gateway needs that)
      ( $page, $response, %reply_headers )
          = $self->https_get( field => 'value', ... );
  
      # or a hashref
      my %hash = ( field => 'value', ... );
      ( $page, $response_code, %reply_headers )
            = $self->https_get( \%hash );
  
      #...
  }

=head1 DESCRIPTION

This is a base class for HTTPS based gateways, providing useful code
for implementors of HTTPS payment APIs.

It depends on Net::SSLeay _or_ ( Crypt::SSLeay and LWP::UserAgent ).

=head1 METHODS

=over 4

=item https_get [ \%options ] HASHREF | FIELD => VALUE, ...

Accepts parameters as either a hashref or a list of fields and values.
In the latter case, ordering is preserved (see L<Tie::IxHash> to do so
when passing a hashref).

Returns a list consisting of the page content as a string, the HTTP
response code and message (i.e. "200 OK" or "404 Not Found"), and a list of
key/value pairs representing the HTTP response headers.

The options hashref supports setting headers and Content-Type:

  {
      headers => { 'X-Header1' => 'value', ... },
      Content-Type => 'text/namevalue',
  }

=cut

sub https_get {
    my $self = shift;

    # handle optional options hashref
    my $opts;
    if ( scalar(@_) > 1 and ref( $_[0] ) eq "HASH" ) {
        $opts = shift;
    }

    # accept a hashref or a list (keep it ordered)
    my $post_data;
    if ( ref( $_[0] ) eq 'HASH' ) {
        $post_data = shift;
    }
    elsif ( scalar(@_) > 1 ) {
        tie my %hash, 'Tie::IxHash', @_;
        $post_data = \%hash;
    }
    elsif ( scalar(@_) == 1 ) {
        $post_data = shift;
    }
    else {
        die "https_get called with no params\n";
    }

    $opts->{"Content-Type"} ||= "application/x-www-form-urlencoded";

    ### XXX referer!!!
    my %headers;
    if ( ref( $opts->{headers} ) eq "HASH" ) {
        %headers = %{ $opts->{headers} };
    }
    $headers{'Host'} ||= $self->server;

    my $path = $self->path;
    if ( keys %$post_data ) {
        $path .= '?'
          . join( '&',
            map { uri_escape($_) . '=' . uri_escape( $post_data->{$_} ) }
              keys %$post_data );
    }

    $self->build_subs(qw( response_page response_code response_headers ));

    if ( $ssl_module eq 'Net::SSLeay' ) {

        import Net::SSLeay qw(get_https make_headers);
        my $headers = make_headers(%headers);

        my( $res_page, $res_code, @res_headers ) =
          get_https( $self->server,
                     $self->port,
                     $path,
                     $headers,
                     "",
                     $opts->{"Content-Type"},
                   );

        $res_code =~ /^(HTTP\S+ )?(.*)/ and $res_code = $2;

        $self->response_page( $res_page );
        $self->response_code( $res_code );
        $self->response_headers( { @res_headers } );

        ( $res_page, $res_code, @res_headers );

    } elsif ( $ssl_module eq 'Crypt::SSLeay' ) {

        import HTTP::Request::Common qw(GET);

        my $url = 'https://' . $self->server;
        $url .= ':' . $self->port
          unless $self->port == 443;
        $url .= "/$path";

        my $ua = new LWP::UserAgent;
        foreach my $hdr ( keys %headers ) {
            $ua->default_header( $hdr => $headers{$hdr} );
        }
        my $res = $ua->request( GET($url) );

        my @res_headers = map { $_ => $res->header($_) }
                              $res->header_field_names;

        $self->response_page( $res->content );
        $self->response_code( $res->code. ' '. $res->message );
        $self->response_headers( { @res_headers } );

        ( $res->content, $res->code. ' '. $res->message, @res_headers );

    } else {
        die "unknown SSL module $ssl_module";
    }

}

=item https_post [ \%options ] SCALAR | HASHREF | FIELD => VALUE, ...

Accepts form fields and values as either a hashref or a list.  In the
latter case, ordering is preserved (see L<Tie::IxHash> to do so when
passing a hashref).

Also accepts instead a simple scalar containing the raw content.

Returns a list consisting of the page content as a string, the HTTP
response code and message (i.e. "200 OK" or "404 Not Found"), and a list of
key/value pairs representing the HTTP response headers.

The options hashref supports setting headers and Content-Type:

  {
      headers => { 'X-Header1' => 'value', ... },
      Content-Type => 'text/namevalue',
  }

=cut

sub https_post {
    my $self = shift;

    # handle optional options hashref
    my $opts;
    if ( scalar(@_) > 1 and ref( $_[0] ) eq "HASH" ) {
        $opts = shift;
    }

    # accept a hashref or a list (keep it ordered)
    my $post_data;
    if ( ref( $_[0] ) eq 'HASH' ) {
        $post_data = shift;
    }
    elsif ( scalar(@_) > 1 ) {
        tie my %hash, 'Tie::IxHash', @_;
        $post_data = \%hash;
    }
    elsif ( scalar(@_) == 1 ) {
        $post_data = shift;
    }
    else {
        die "https_post called with no params\n";
    }

    $opts->{"Content-Type"} ||= "application/x-www-form-urlencoded";

    ### XXX referer!!!
    my %headers;
    if ( ref( $opts->{headers} ) eq "HASH" ) {
        %headers = %{ $opts->{headers} };
    }
    $headers{'Host'} ||= $self->server;

    if ( $DEBUG && ref($post_data) ) {
        warn "post data:\n",
          join( '',
            map { "  $_ => " . $post_data->{$_} . "\n" } keys %$post_data );
    }

    $self->build_subs(qw( response_page response_code response_headers ));

    if ( $ssl_module eq 'Net::SSLeay' ) {

        import Net::SSLeay qw(post_https make_headers make_form);
        my $headers = make_headers(%headers);

        if ($DEBUG) {
            no warnings 'uninitialized';
            warn $self->server . ':' . $self->port . $self->path . "\n";
            $Net::SSLeay::trace = $DEBUG;
        }

        my $raw_data = ref($post_data) ? make_form(%$post_data) : $post_data;

        my( $res_page, $res_code, @res_headers ) =
          post_https( $self->server,
                      $self->port,
                      $self->path,
                      $headers,
                      $raw_data,
                      $opts->{"Content-Type"},
                    );

        $res_code =~ /^(HTTP\S+ )?(.*)/ and $res_code = $2;

        $self->response_page( $res_page );
        $self->response_code( $res_code );
        $self->response_headers( { @res_headers } );

        ( $res_page, $res_code, @res_headers );

    } elsif ( $ssl_module eq 'Crypt::SSLeay' ) {

        import HTTP::Request::Common qw(POST);

        my $url = 'https://' . $self->server;
        $url .= ':' . $self->port
          unless $self->port == 443;
        $url .= $self->path;

        if ($DEBUG) {
            warn $url;
        }

        my $ua = new LWP::UserAgent;
        foreach my $hdr ( keys %headers ) {
            $ua->default_header( $hdr => $headers{$hdr} );
        }

        my $res;
        if ( ref($post_data) ) {
            $res = $ua->request( POST( $url, [%$post_data] ) );
        }
        else {
            my $req = new HTTP::Request( 'POST' => $url );
            $req->content_type( $opts->{"Content-Type"} );
            $req->content($post_data);
            $res = $ua->request($req);
        }

        my @res_headers = map { $_ => $res->header($_) }
                              $res->header_field_names;

        $self->response_page( $res->content );
        $self->response_code( $res->code. ' '. $res->message );
        $self->response_headers( { @res_headers } );

        ( $res->content, $res->code. ' '. $res->message, @res_headers );

    } else {
        die "unknown SSL module $ssl_module";
    }

}

=back

=head1 SEE ALSO

L<Business::OnlinePayment>

=cut

1;
