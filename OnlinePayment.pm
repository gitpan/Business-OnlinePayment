package Business::OnlinePayment;

use strict;
use vars qw($VERSION);
use Carp;

require 5.005;

$VERSION = '3.00_09';
$VERSION = eval $VERSION; # modperlstyle: convert the string into a number

# Remember subclasses we have "wrapped" submit() with _pre_submit()
my %Presubmit_Added = ();

my %fields = (
    authorization        => undef,
    error_message        => undef,
    failure_status       => undef,
    fraud_detect         => undef,
    is_success           => undef,
    maximum_risk         => undef,
    path                 => undef,
    port                 => undef,
    require_avs          => undef,
    result_code          => undef,
    server               => undef,
    server_response      => undef,
    test_transaction     => undef,
    transaction_type     => undef,
    fraud_score          => undef,
    fraud_transaction_id => undef,
);

sub new {
    my($class,$processor,%data) = @_;

    croak("unspecified processor") unless $processor;

    my $subclass = "${class}::$processor";
    eval "use $subclass";
    croak("unknown processor $processor ($@)") if $@;

    my $self = bless {processor => $processor}, $subclass;
    $self->build_subs(keys %fields);

    if($self->can("set_defaults")) {
        $self->set_defaults(%data);
    }

    foreach(keys %data) {
        my $key = lc($_);
        my $value = $data{$_};
        $key =~ s/^\-+//;
        $self->build_subs($key);
        $self->$key($value);
    }

    # "wrap" submit with _pre_submit only once
    unless ( $Presubmit_Added{$subclass} ) {
        my $real_submit = $subclass->can('submit');

	no warnings 'redefine';
	no strict 'refs';

	*{"${subclass}::submit"} = sub {
	    my $self = shift;
	    return unless $self->_pre_submit(@_);
	    return $real_submit->($self, @_);
	}
    }

    return $self;
}

sub _risk_detect {
    my ($self, $risk_transaction) = @_;

    my %parent_content = $self->content();
    $parent_content{action} = 'Fraud Detect';
    $risk_transaction->content( %parent_content );
    $risk_transaction->submit();
    if ($risk_transaction->is_success()) {
         $self->fraud_score( $risk_transaction->fraud_score );
         $self->fraud_transaction_id( $risk_transaction->fraud_transaction_id );
	if ( $risk_transaction->fraud_score <= $self->maximum_fraud_score()) {
	    return 1;
	} else {
	    $self->error_message('Excessive risk from risk management');
	}
    } else {
	$self->error_message('Error in risk detection stage: ' .  $risk_transaction->error_message);
    }
    $self->is_success(0);
    return 0;
}

my @Fraud_Class_Path = qw(Business::OnlinePayment Business::FraudDetect);

sub _pre_submit {
    my ($self) = @_;
    my $fraud_detection = $self->fraud_detect();

    # early return if user does not want optional risk mgt
    return 1 unless $fraud_detection;

    # Search for an appropriate FD module
    foreach my $fraud_class ( @Fraud_Class_Path ) {
	my $subclass = $fraud_class . "::" . $fraud_detection;
	eval "use $subclass ()";
	if ($@) {
	    croak("error loading fraud_detection module ($@)")
              unless ( $@ =~ m/^Can\'t locate/ );
        } else {
            my $risk_tx = bless( { processor => $fraud_detection }, $subclass );
            $risk_tx->build_subs(keys %fields);
            if ($risk_tx->can('set_defaults')) {
                $risk_tx->set_defaults();
            }
            $risk_tx->_glean_parameters_from_parent($self);
            return $self->_risk_detect($risk_tx);
	}
    }
    croak("Unable to locate fraud_detection module $fraud_detection"
		. " in \@INC under Fraud_Class_Path (\@Fraud_Class_Path"
	        . " contains: @Fraud_Class_Path) (\@INC contains: @INC)");
}

sub content {
    my($self,%params) = @_;

    if(%params) {
        if($params{'type'}) { $self->transaction_type($params{'type'}); }
        %{$self->{'_content'}} = %params;
    }
    return exists $self->{'_content'} ? %{$self->{'_content'}} : ();
}

sub required_fields {
    my($self,@fields) = @_;

    my @missing;
    my %content = $self->content();
    foreach(@fields) {
        push(@missing, $_) unless exists $content{$_};
    }

    croak("missing required field(s): " . join(", ", @missing) . "\n")
	  if(@missing);
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

    croak("Processor subclass did not override submit function");
}

sub dump_contents {
    my($self) = @_;

    my %content = $self->content();
    my $dump = "";
    foreach(sort keys %content) {
        $dump .= "$_ = $content{$_}\n";
    }
    return $dump;
}

# didnt use AUTOLOAD because Net::SSLeay::AUTOLOAD passes right to
# AutoLoader::AUTOLOAD, instead of passing up the chain
sub build_subs {
    my $self = shift;

    foreach(@_) {
        next if($self->can($_));
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
                        type        => 'Visa',
                        amount      => '49.95',
                        card_number => '1234123412341238',
                        expiration  => '0100',
                        name        => 'John Q Doe',
                       );
  $transaction->submit();
  
  if($transaction->is_success()) {
    print "Card processed successfully: ", $transaction->authorization(), "\n";
  } else {
    print "Card was rejected: ", $transaction->error_message(), "\n";
  }

=head1 DESCRIPTION

Business::OnlinePayment is a generic module for processing payments
through online credit card processors, electronic cash systems, etc.

=head1 METHODS AND FUNCTIONS

=head2 new($processor, %processor_options);

Create a new Business::OnlinePayment object, $processor is required,
and defines the online processor to use.  If necessary, processor
options can be specified, currently supported options are 'Server',
'Port', and 'Path', which specify how to find the online processor
(https://server:port/path), but individual processor modules should
supply reasonable defaults for this information, override the defaults
only if absolutely necessary (especially path), as the processor
module was probably written with a specific target script in mind.

=head2 content(%content);

The information necessary for the transaction, this tends to vary a
little depending on the processor, so we have chosen to use a system
which defines specific fields in the frontend which get mapped to the
correct fields in the backend.  The currently defined fields are:

=head3 PROCESSOR FIELDS

=over 4

=item * login

Your login name to use for authentication to the online processor.

=item * password

Your password to use for authentication to the online processor.

=back

=head3 GENERAL TRANSACTION FIELDS

=over 4

=item * type

Transaction type, supported types are: CC (credit card), ECHECK
(electronic check) and LEC (phone bill billing).  Deprecated types
are: Visa, MasterCard, American Express, Discover, Check (not all
processors support all these transaction types).

=item * action

What to do with the transaction (currently available are: Normal
Authorization, Authorization Only, Credit, Post Authorization,
Recurring Authorization, Modify Recurring Authorization,
Cancel Recurring Authorization)

=item * description

A description of the transaction (used by some processors to send
information to the client, normally not a required field).

=item * amount

The amount of the transaction, most processors don't want dollar signs
and the like, just a floating point number.

=item * invoice_number

An invoice number, for your use and not normally required, many
processors require this field to be a numeric only field.

=back

=head3 CUSTOMER INFO FIELDS

=over 4

=item * customer_id

A customer identifier, again not normally required.

=item * name

The customer's name, your processor may not require this.

=item * first_name

=item * last_name

The customer's first and last name as separate fields.

=item * company

The customer's company name, not normally required.

=item * address

The customer's address (your processor may not require this unless you
are requiring AVS Verification).

=item * city

The customer's city (your processor may not require this unless you
are requiring AVS Verification).

=item * state

The customer's state (your processor may not require this unless you
are requiring AVS Verification).

=item * zip

The customer's zip code (your processor may not require this unless
you are requiring AVS Verification).

=item * country

Customer's country.

=item * ship_first_name

=item * ship_last_name

=item * ship_company

=item * ship_address

=item * ship_city

=item * ship_state

=item * ship_zip

=item * ship_country

These shipping address fields may be accepted by your processor.
Refer to the description for the corresponding non-ship field for
general information on each field.

=item * phone

Customer's phone number.

=item * fax

Customer's fax number.

=item * email

Customer's email address.

=item * customer_ip

IP Address from which the transaction originated.

=back

=head3 CREDIT CARD FIELDS

=over 4

=item * card_number

Credit card number.

=item * cvv2

CVV2 number (also called CVC2 or CID) is a three- or four-digit
security code used to reduce credit card fraud.

=item * expiration

Credit card expiration.

=item * track1

Track 1 on the magnetic stripe (Card present only)

=item * track2

Track 2 on the magnetic stripe (Card present only)

=item * recurring billing

Recurring billing flag

=back

=head3 ELECTRONIC CHECK FIELDS

=over 4

=item * account_number

Bank account number for electronic checks or electronic funds
transfer.

=item * routing_code

Bank's routing code for electronic checks or electronic funds
transfer.

=item * account_type

Account type for electronic checks or electronic funds transfer.  Can be
(case-insensitive): B<Personal Checking>, B<Personal Savings>,
B<Business Checking> or B<Business Savings>.

=item * account_name

Account holder's name for electronic checks or electronic funds
transfer.

=item * bank_name

Bank's name for electronic checks or electronic funds transfer.

=item * check_type

Check type for electronic checks or electronic funds transfer.

=item * customer_org

Customer organization type.

=item * customer_ssn

Customer's social security number.  Typically only required for
electronic checks or electronic funds transfer.

=item * license_num

Customer's driver's license number.  Typically only required for
electronic checks or electronic funds transfer.

=item * license_dob

Customer's date of birth.  Typically only required for electronic
checks or electronic funds transfer.

=back

=head3 RECURRING BILLING FIELDS

=over 4

=item * interval 

Interval expresses the amount of time between billings: digits, whitespace
and units (currently "days" or "months" in either singular or plural form).

=item * start

The date of the first transaction (used for processors which allow delayed
start) expressed as YYYY-MM-DD.

=item * periods

The number of cycles of interval length for which billing should occur 
(inclusive of 'trial periods' if the processor supports recurring billing
at more than one rate)

=back

=head2 submit();

Submit the transaction to the processor for completion

=head2 is_success();

Returns true if the transaction was submitted successfully, false if
it failed (or undef if it has not been submitted yet).

=head2 failure_status();

If the transaction failed, it can optionally return a specific failure
status (normalized, not gateway-specific).  Currently defined statuses
are: "expired", "nsf" (non-sufficient funds), "stolen", "pickup",
"blacklisted" and "declined" (card/transaction declines only, not
other errors).

Note that (as of Aug 2006) this is only supported by some of the
newest processor modules, and that, even if supported, a failure
status is an entirely optional field that is only set for specific
kinds of failures.

=head2 result_code();

Returns the precise result code that the processor returned, these are
normally one letter codes that don't mean much unless you understand
the protocol they speak, you probably don't need this, but it's there
just in case.

=head2 test_transaction();

Most processors provide a test mode, where submitted transactions will
not actually be charged or added to your batch, calling this function
with a true argument will turn that mode on if the processor supports
it, or generate a fatal error if the processor does not support a test
mode (which is probably better than accidentally making real charges).

=head2 require_avs();

Providing a true argument to this module will turn on address
verification (if the processor supports it).

=head2 transaction_type();

Retrieve the transaction type (the 'type' argument to contents()).
Generally only used internally, but provided in case it is useful.

=head2 error_message();

If the transaction has been submitted but was not accepted, this
function will return the provided error message (if any) that the
processor returned.

=head2 authorization();

If the transaction has been submitted and accepted, this function will
provide you with the authorization code that the processor returned.

=head2 server();

Retrieve or change the processor submission server address (CHANGE AT
YOUR OWN RISK).

=head2 port();

Retrieve or change the processor submission port (CHANGE AT YOUR OWN
RISK).

=head2 path();

Retrieve or change the processor submission path (CHANGE AT YOUR OWN
RISK).

=head2 fraud_score();

Retrieve or change the fraud score from any Business::FraudDetect plugin

=head2 fraud_transaction_id();

Retrieve or change the transaction id from any Business::FraudDetect plugin

=head1 AUTHORS

Jason Kohles, email@jasonkohles.com

(v3 rewrite) Ivan Kohler <ivan-business-onlinepayment@420.am>

Phil Lobbes E<lt>phil at perkpartners dot comE<gt>

=head1 MAILING LIST

Please direct current development questions, patches, etc. to the mailing list:
http://420.am/cgi-bin/mailman/listinfo/bop-devel/

=head1 DISCLAIMER

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=head1 SEE ALSO

http://420.am/business-onlinepayment/

For verification of credit card checksums, see L<Business::CreditCard>.

=cut
