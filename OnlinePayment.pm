package Business::OnlinePayment;

use strict;
use vars qw($VERSION); # @ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use Carp;

require 5.004;
#require Exporter;

#@ISA = (); #qw(Exporter AutoLoader);
#@EXPORT = qw();
#@EXPORT_OK = qw();

$VERSION = '3.00_01';
sub VERSION { #Argument "3.00_01" isn't numeric in subroutine entry
  local($^W)=0;
  UNIVERSAL::VERSION(@_);
}

my %fields = (
    is_success       => undef,
    result_code      => undef,
    test_transaction => undef,
    require_avs      => undef,
    transaction_type => undef,
    error_message    => undef,
    authorization    => undef,
    server           => undef,
    port             => undef,
    path             => undef,
    server_response  => undef,
);


sub new {
    my($class,$processor,%data) = @_;

    Carp::croak("unspecified processor") unless $processor;

    my $subclass = "${class}::$processor";
    if(!defined(&$subclass)) {
        eval "use $subclass";
        Carp::croak("unknown processor $processor ($@)") if $@;
    }

    my $self = bless {processor => $processor}, $subclass;
    $self->build_subs(keys %fields);

    if($self->can("set_defaults")) {
        $self->set_defaults();
    }

    foreach(keys %data) {
        my $key = lc($_);
        my $value = $data{$_};
        $key =~ s/^\-//;
        $self->build_subs($key);
        $self->$key($value);
    }

    return $self;
}

sub content {
    my($self,%params) = @_;

    if(%params) {
        if($params{'type'}) { $self->transaction_type($params{'type'}); }
        %{$self->{'_content'}} = %params;
    }
    return %{$self->{'_content'}};
}

sub required_fields {
    my($self,@fields) = @_;

    my %content = $self->content();
    foreach(@fields) {
        Carp::croak("missing required field $_") unless exists $content{$_};
    }
}

sub get_fields {
    my($self, @fields) = @_;

    my %content = $self->content();

    #my %new = ();
    #foreach(@fields) { $new{$_} = $content{$_}; }
    #return %new;
    map { $_ => $content{$_} } grep defined $content{$_}, @fields;
}

sub remap_fields {
    my($self,%map) = @_;

    my %content = $self->content();
    foreach( keys %map ) {
        $content{$map{$_}} = $content{$_};
    }
    $self->content(%content);
}

sub submit {
    my($self) = @_;

    Carp::croak("Processor subclass did not override submit function");
}

sub dump_contents {
    my($self) = @_;

    my %content = $self->content();
    my $dump = "";
    foreach(keys %content) {
        $dump .= "$_ = $content{$_}\n";
    }
    return $dump;
}

# didnt use AUTOLOAD because Net::SSLeay::AUTOLOAD passes right to
# AutoLoader::AUTOLOAD, instead of passing up the chain
sub build_subs {
    my $self = shift;
    foreach(@_) {
        eval "sub $_ { my \$self = shift; if(\@_) { \$self->{$_} = shift; } return \$self->{$_}; }";
    }
}

1;

__END__

=head1 NAME

Business::OnlinePayment - Perl extension for online payment processing

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $transaction = new Business::OnlinePayment($processor, %processor_info);
  $transaction->content(
                        type       => 'Visa',
                        amount     => '49.95',
                        cardnumber => '1234123412341238',
                        expiration => '0100',
                        name       => 'John Q Doe',
                       );
  $transaction->submit();

  if($transaction->is_success()) {
    print "Card processed successfully: ".$transaction->authorization()."\n";
  } else {
    print "Card was rejected: ".$transaction->error_message()."\n";
  }

=head1 DESCRIPTION

Business::OnlinePayment is a generic module for processing payments through
online credit card processors, electronic cash systems, etc.

=head1 METHODS AND FUNCTIONS

=head2 new($processor, %processor_options);

Create a new Business::OnlinePayment object, $processor is required, and defines the online processor to use.  If necessary, processor options can be specified, currently supported options are 'Server', 'Port', and 'Path', which specify how to find the online processor (https://server:port/path), but individual processor modules should supply reasonable defaults for this information, override the defaults only if absolutely necessary (especially path), as the processor module was probably written with a specific target script in mind.

=head2 content(%content);

The information necessary for the transaction, this tends to vary a little depending on the processor, so we have chosen to use a system which defines specific fields in the frontend which get mapped to the correct fields in the backend.  The currently defined fields are:

=over 4

=item * type

Transaction type, supported types are:
Visa, MasterCard, American Express, Discover, Check (not all processors support all these transaction types).

=item * login

Your login name to use for authentication to the online processor.

=item * password

Your password to use for authentication to the online processor.

=item * action

What to do with the transaction (currently available are: Normal Authorization, Authorization Only, Credit, Post Authorization)

=item * description

A description of the transaction (used by some processors to send information to the client, normally not a required field).

=item * amount

The amount of the transaction, most processors dont want dollar signs and the like, just a floating point number.

=item * invoice_number

An invoice number, for your use and not normally required, many processors require this field to be a numeric only field.

=item * customer_id

A customer identifier, again not normally required.

=item * name

The customers name, your processor may not require this.

=item * address

The customers address (your processor may not require this unless you are requiring AVS Verification).

=item * city

The customers city (your processor may not require this unless you are requiring AVS Verification).

=item * state

The customers state (your processor may not require this unless you are requiring AVS Verification).

=item * zip

The customers zip code (your processor may not require this unless you are requiring AVS Verification).

=item * country

Customer's country.

=item * phone

Customer's phone number.

=item * fax

Customer's fax number.

=item * email

Customer's email address.

=item * card_number

Credit card number (obviously not required for non-credit card transactions).

=item * exp_date

Credit card expiration (obviously not required for non-credit card transactions).

=item * account_number

Bank account number for electronic checks or electronic funds transfer.

=item * routing_code

Bank's routing code for electronic checks or electronic funds transfer.

=item * bank_name

Bank's name for electronic checks or electronic funds transfer.

=back

=head2 submit();

Submit the transaction to the processor for completion

=head2 is_success();

Returns true if the transaction was submitted successfully, false if it failed (or undef if it has not been submitted yet).

=head2 result_code();

Returns the precise result code that the processor returned, these are normally one letter codes that don't mean much unless you understand the protocol they speak, you probably don't need this, but it's there just in case.

=head2 test_transaction();

Most processors provide a test mode, where submitted transactions will not actually be charged or added to your batch, calling this function with a true argument will turn that mode on if the processor supports it, or generate a fatal error if the processor does not support a test mode (which is probably better than accidentally making real charges).

=head2 require_avs();

Providing a true argument to this module will turn on address verification (if the processor supports it).

=head2 transaction_type();

Retrieve the transaction type (the 'type' argument to contents();).  Generally only used internally, but provided in case it is useful.

=head2 error_message();

If the transaction has been submitted but was not accepted, this function will return the provided error message (if any) that the processor returned.

=head2 authorization();

If the transaction has been submitted and accepted, this function will provide you with the authorization code that the processor returned.

=head2 server();

Retrieve or change the processor submission server address (CHANGE AT YOUR OWN RISK).

=head2 port();

Retrieve or change the processor submission port (CHANGE AT YOUR OWN RISK).

=head2 path();

Retrieve or change the processor submission path (CHANGE AT YOUR OWN RISK).

=head1 AUTHORS

Jason Kohles, email@jasonkohles.com

(v3 rewrite) Ivan Kohler <ivan-business-onlinepayment@420.am>

=head1 DISCLAIMER

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.


=head1 SEE ALSO

http://420.am/business-onlinepayment/

For verification of credit card checksums, see L<Business::CreditCard>.

=cut
