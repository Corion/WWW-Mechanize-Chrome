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

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    my $version = $mech->chrome_version;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    $mech->autodie(1);

    t::helper::safe_get_local($mech, '50-click.html');
    $mech->allow('javascript' => 1);

    my ($win,$type,$ok);

    eval {
        $win = t::helper::safe_selector($mech, '#open_window', single => 1);
        $ok = 1;
    };

    if (! $win) {
        SKIP: { skip "Couldn't get at 'open_window'. Do you have a Javascript blocker?", 15; };
        return;
    };

    ok $win, "We found 'open_window'";
    if( $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 == 61 or $1 == 60) and $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE}) {
        SKIP: {
            skip "Chrome 60,61 opening windows doesn't play well with in-process tests", 1;
            # This is mostly taking PNG screenshots afterwards that fails,
            # t/56-*.t
        };
    } else {
        t::helper::safe_click($mech, $win, synchronize => 0);
        ok 1, "We get here";
    };
    note "But we don't know what window was opened";
    #sleep 10;
    # or how to close it

    note "End of test sub for $browser_instance";
});

alarm(0);
