#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 19*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 19, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    t::helper::safe_get_local($mech, '51-mech-submit.html');

    my ($triggered,$type,$ok);
    eval {
        ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');
        $ok = 1;
    };
    if (! $triggered) {
        SKIP: { skip "Couldn't get at 'myevents'. Do you have a Javascript blocker?", 10; };
        exit;
    };
    ok $triggered, "We have JS enabled";

    $mech->allow('javascript' => 1);
    t::helper::safe_form_id($mech, 'testform');

    t::helper::safe_field($mech, 'q','1');
    t::helper::safe_submit($mech);

    ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 0, 'OnSubmit was not triggered (no user interaction)';
    is $triggered->{click},  0, 'Click    was not triggered';

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    $mech->allow('javascript' => 1);
    t::helper::safe_submit_form($mech, 
        with_fields => {
            r => 'Hello Chrome',
        },
    );
    ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');
    ok $triggered, "We found 'myevents'";

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 0, 'OnSubmit was triggered (no user interaction)';
    is $triggered->{click},  0, 'Click    was not triggered';
    my $r = t::helper::safe_xpath($mech, '//input[@name="r"]', single => 1 );
    is $r->get_attribute('value'), 'Hello Chrome', "We set the new value";
    $r->set_attribute('value', 'Hello Chrome2');
    # Somehow we lose the node id resp. fetch a stale value here without re-fetching
    $r = t::helper::safe_xpath($mech, '//input[@name="r"]', single => 1 );
    is $r->get_attribute('value'), 'Hello Chrome2', "We retrieve the new value via ->get_attribute";
    t::helper::safe_form_number($mech, 2);
    is t::helper::safe_value($mech, 'r'), 'Hello Chrome2', "We retrieve set the new value via ->value()";

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    $mech->allow('javascript' => 1);
    t::helper::safe_submit_form($mech, button => 's');
    ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');
    ok $triggered, "We found 'myevents'";

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 1, 'OnSubmit was triggered';
    is $triggered->{click},  1, 'Click    was triggered';

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    $mech->allow('javascript' => 1);
    t::helper::safe_form_number($mech, 1);
    t::helper::safe_submit_form($mech);
    ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');
    ok $triggered, "We can submit an empty form";

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    $mech->allow('javascript' => 1);
    t::helper::safe_form_number($mech, 3);
    t::helper::safe_submit_form($mech);
    like $mech->uri, qr/q2=Hello(%20|\+)World(%20|\+)C/, "We submit the proper GET request";
    ($triggered) = t::helper::safe_eval_in_page($mech, 'myevents');
    ok $triggered, "We can submit a form without an onsubmit handler";
});

alarm(0);
