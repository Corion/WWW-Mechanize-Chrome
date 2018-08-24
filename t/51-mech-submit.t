#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 19*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 17, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('51-mech-submit.html');

    my ($triggered,$type,$ok);
    eval {
        ($triggered) = $mech->eval_in_page('myevents');
        $ok = 1;
    };
    if (! $triggered) {
        SKIP: { skip "Couldn't get at 'myevents'. Do you have a Javascript blocker?", 10; };
        exit;
    };
    ok $triggered, "We have JS enabled";

    $mech->allow('javascript' => 1);
    $mech->form_id('testform');

    $mech->field('q','1');
    $mech->submit();

    ($triggered) = $mech->eval_in_page('myevents');

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 0, 'OnSubmit was not triggered (no user interaction)';
    is $triggered->{click},  0, 'Click    was not triggered';

    $mech->get_local('51-mech-submit.html');
    $mech->allow('javascript' => 1);
    $mech->submit_form(
        with_fields => {
            r => 'Hello Chrome',
        },
    );
    ($triggered) = $mech->eval_in_page('myevents');
    ok $triggered, "We found 'myevents'";

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 0, 'OnSubmit was triggered (no user interaction)';
    is $triggered->{click},  0, 'Click    was not triggered';
    my $r = $mech->xpath('//input[@name="r"]', single => 1 );
    is $r->get_attribute('value'), 'Hello Chrome', "We set the new value";
    $r->set_attribute('value', 'Hello Chrome2');
    # Somehow we lose the node id resp. fetch a stale value here without re-fetching
    $r = $mech->xpath('//input[@name="r"]', single => 1 );
    is $r->get_attribute('value'), 'Hello Chrome2', "We retrieve the new value via ->get_attribute";
    $mech->form_number(2);
    is $mech->value('r'), 'Hello Chrome2', "We retrieve set the new value via ->value()";
    
    $mech->get_local('51-mech-submit.html');
    $mech->allow('javascript' => 1);
    $mech->submit_form(button => 's');
    ($triggered) = $mech->eval_in_page('myevents');
    ok $triggered, "We found 'myevents'";

    is $triggered->{action}, 1, 'Action   was triggered';
    is $triggered->{submit}, 1, 'OnSubmit was triggered';
    is $triggered->{click},  1, 'Click    was triggered';

    $mech->get_local('51-mech-submit.html');
    $mech->allow('javascript' => 1);
    $mech->form_number(1);
    $mech->submit_form();
    ($triggered) = $mech->eval_in_page('myevents');
    ok $triggered, "We can submit an empty form";

    $mech->get_local('51-mech-submit.html');
    $mech->allow('javascript' => 1);
    $mech->form_number(3);
    $mech->submit_form();
    like $mech->uri, qr/q2=Hello(%20|\+)World(%20|\+)C/, "We submit the proper GET request";
    ($triggered) = $mech->eval_in_page('myevents');
    ok $triggered, "We can submit a form without an onsubmit handler";
});

$server->kill;
undef $server;
#wait; # gobble up our child process status