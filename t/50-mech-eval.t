#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 4;

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

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my ($val, $type) = t::helper::safe_eval($mech, 'new Object');
    is $type, "object", "We can create simple objects and serialize them as JSON";

    ($val, $type) = t::helper::safe_eval($mech, 'window', returnByValue => JSON::false);
    is $type, "object", "We can also return (proxies for) unserializable objects";

    ($val, $type) = t::helper::safe_callFunctionOn($mech, 'function add(a,b){ return a+b }', arguments => [ {value => 2 }, { value => 2 }]);
    is $val, 4, "We can call functions without manually encoding parameters";

    note "End of test sub for $browser_instance";
});

alarm(0);
