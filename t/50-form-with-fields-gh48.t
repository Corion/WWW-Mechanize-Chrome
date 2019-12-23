use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 3;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    $mech->get_local('50-form-with-fields-gh48.html');
#$mech->dump_forms;

    ## Works:
    my $ok = eval {
        $mech->form_name('signIn');
        1;
    };
    my $err = $@;
    is $err, '', "We got no error on selecting the form by form name";

    # Just checking.. yup its there:
    #my @text = $mech->selector('#ap_email');
    #say $_->get_attribute('outerHTML') for @text;
    #
    #my @text = $mech->xpath('//input[@id="#ap_email"]');
    #say $_->get_attribute('outerHTML') for @text;

    # Works
    $ok = eval {
        $mech->form_with_fields('email', 'password');
        1
    };
    $err = $@;
    is $err, '', "We got no error on selecting the form by field name";

    #print $mech->current_form()->get_attribute('outerHTML');
    # Fails! (well, no more)
    $ok = eval {
        $mech->submit_form(with_fields => {email => 'foo@bar.baz'});
    };
    $err = $@;
    is $err, '', "We got no error on submitting the form by field name";
});
