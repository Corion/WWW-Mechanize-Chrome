#!/usr/bin/perl -w

# file 50-form3.t
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc';
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
    plan tests => 8*@instances;
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

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 8, sub {
    my ($browser_instance, $mech) = @_;

    $mech->get_local('50-form3.html');
    $mech->form_number(1);
    my $the_form_dom_node = $mech->current_form;
    my $button = $mech->selector('#btn_ok', single => 1);
    isa_ok $button, 'WWW::Mechanize::Chrome::Node', "The button image";

    ok $mech->submit, 'Sent the page';

    $mech->get_local('50-form3.html');
    @{$mech->{event_log}} = ();
    $mech->form_id('snd');
    if(! ok $mech->current_form, "We can find a form by its id") {
        for (@{$mech->{event_log}}) {
            diag $_
        };
    };

    $mech->get_local('50-form3.html');
    $mech->form_with_fields('r1[name]');
    ok $mech->current_form, "We can find a form by its contained input fields (single,matched)";

    $mech->get_local('50-form3.html');
    $mech->form_with_fields('r1[name]','r2[name]');
    ok $mech->current_form, "We can find a form by its contained input fields (double,matched)";

    $mech->get_local('50-form3.html');
    $mech->form_with_fields('r3name]');
    ok $mech->current_form, "We can find a form by its contained input fields (single,closing)";

    $mech->get_local('50-form3.html');
    $mech->form_with_fields('r4[name');
    ok $mech->current_form, "We can find a form by its contained input fields (single,opening)";

    $mech->get_local('50-form3.html');
    $mech->form_name('snd');
    ok $mech->current_form, "We can find a form by its name";
});