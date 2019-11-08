#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';

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
    plan tests => 3*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, 3, sub {
    my ($browser_instance, $mech) = @_;
    my $version = $mech->chrome_version;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    $mech->autodie(1);

    $mech->get_local('50-click.html');
    $mech->allow('javascript' => 1);

    my ($win,$type,$ok);

    eval {
        $win = $mech->selector('#open_window', single => 1);
        $ok = 1;
    };

    if (! $win) {
        SKIP: { skip "Couldn't get at 'open_window'. Do you have a Javascript blocker?", 15; };
        exit;
    };

    ok $win, "We found 'open_window'";
    if( $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 == 61 or $1 == 60) and $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE}) {
        SKIP: {
            skip "Chrome 60,61 opening windows doesn't play well with in-process tests", 1;
            # This is mostly taking PNG screenshots afterwards that fails,
            # t/56-*.t
        };
    } else {
        $mech->click($win, synchronize => 0);
        ok 1, "We get here";
    };
    note "But we don't know what window was opened";
    #sleep 10;
    # or how to close it
});
