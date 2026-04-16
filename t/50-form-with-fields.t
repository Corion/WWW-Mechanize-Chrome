#!/usr/bin/perl -w

# file 50-form3.t
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
    plan tests => 8*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 8, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_number($mech, 1);
    my $the_form_dom_node = $mech->current_form;
    my $button = t::helper::safe_selector($mech, '#btn_ok', single => 1);
    isa_ok $button, 'WWW::Mechanize::Chrome::Node', "The button image";

    ok t::helper::safe_submit($mech), 'Sent the page';

    t::helper::safe_get_local($mech, '50-form3.html');
    @{$mech->{event_log}} = ();
    t::helper::safe_form_id($mech, 'snd');
    if(! ok $mech->current_form, "We can find a form by its id") {
        for (@{$mech->{event_log}}) {
            diag $_
        };
    };

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_with_fields($mech, 'r1[name]');
    ok $mech->current_form, "We can find a form by its contained input fields (single,matched)";

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_with_fields($mech, 'r1[name]','r2[name]');
    ok $mech->current_form, "We can find a form by its contained input fields (double,matched)";

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_with_fields($mech, 'r3name]');
    ok $mech->current_form, "We can find a form by its contained input fields (single,closing)";

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_with_fields($mech, 'r4[name');
    ok $mech->current_form, "We can find a form by its contained input fields (single,opening)";

    t::helper::safe_get_local($mech, '50-form3.html');
    t::helper::safe_form_name($mech, 'snd');
    ok $mech->current_form, "We can find a form by its name";

    note "End of test sub for $browser_instance";
});

alarm(0);

