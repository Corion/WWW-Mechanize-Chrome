use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use WWW::Mechanize::Chrome::URLBlacklist;
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 6;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

#my $bl = WWW::Mechanize::Chrome::URLBlacklist->new(
#    blacklist => [
#    ],
#    whitelist => [
#        qr!localhost!,
#        qr!^file://!,
#    ],
#
#    # fail all unknown URLs
#    default => 'failRequest',
#    # allow all unknown URLs
#    # default => 'continueRequest',
#
#    on_default => sub {
#        warn "*** Ignored URL $_[0] (action was '$_[1]')",
#    },
#);

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $mech = WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
    #$bl->enable($mech);
    return $mech;
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    $mech->get_local('50-form-with-fields-gh48.html');
    # A second attempt, to cycle the node ids quickly to avoid a node id 0
    $mech->get_local('50-form-with-fields-gh48.html');
    note "Loaded page";
#$mech->dump_forms;
    my $f;
    my $ok = eval {
        $f = $mech->current_form();
        1;
    };
    my $err = $@;
    is $err, '', "No fatal error when retrieving ->current_form() again";
    if( isnt $f, undef, "We have a form" ) {
        note "Retrieving HTML from ->current_form()";
        my $html = $mech->current_form()->get_attribute('outerHTML');
        like $html, qr/^<form/i, "The form outer HTML looks like we expect";
    } else {
        SKIP: {
            skip "No form, no HTML to check", 1;
        };
    };

    ## Works:
    $ok = eval {
        $mech->form_name('signIn');
        1;
    };
    $err = $@;
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
