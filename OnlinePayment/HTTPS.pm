package Business::OnlinePayment::HTTPS;

use strict;
use vars qw($VERSION @ISA $ssl_module $skip_NetSSLeay);
#use URI;
#use URI::QueryParam;
use URI::Escape;
use Tie::IxHash;

@ISA = qw( Business::OnlinePayment );

$VERSION = '0.01';

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
                die "Net::SSLeay (+URI) or Crypt::SSLeay (+LWP) is required";
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

    my $ua = new LWP::UserAgent;
    my $res = $ua->request(
      GET( 'https://'. $self->server. ':'. $self->port. '/'. $path )
    );

    #( $res->as_string, # wtf?
    ( $res->content,
      $res->code,
      map { $_ => $res->header($_) } $res->header_field_names
    );

  } else {

    die "unknown SSL module $ssl_module";

  }

}

=item https_post

Not yet implemented

=cut

sub https_post {
  my $self = shift;

  die "not yet implemented";
}

=back

=head1 SEE ALSO 

L<Business::OnlinePayment>

=cut

1;

