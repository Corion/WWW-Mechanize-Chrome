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
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my ($browser_instance, $mech) = @_;
    my $version = $mech->chrome_version;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    $mech->get_local('50-click.html');
    my ($ok, $clicked, $type);
    eval {
        ($clicked, $type) = $mech->eval_in_page('clicked');
        $ok = 1;
    };
    diag $@ if $@;

    if (! $clicked) {
        SKIP: { skip "Couldn't get at 'clicked'. Do you have a Javascript blocker?", 8; };
        return;
    };

    ok $clicked, "We found 'clicked'";

    #$mech->click({ selector => '#a_div', intrapage => 1 });
    $mech->click({ selector => '#a_div' });
    pass "We can click on elements that only perform an intrapage action and not wait";
    ($clicked,$type) = $mech->eval_in_page('clicked');
    is $clicked, 'a_div', "We register the click";
});
