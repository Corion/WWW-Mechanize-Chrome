#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';

use Test::HTTP::LocalServer;
use Data::Dumper;

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 6*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $m = WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

my $server = t::helper->safe_server(
    #debug => 1,
);

sub get_viewport_size {
    my( $mech ) = @_;
    my ($width,$height,$wwidth,$wheight,$type);
    ($width,$type)  = t::helper::safe_eval_in_page($mech, 'window.screen.width' );
    ($height,$type) = t::helper::safe_eval_in_page($mech, 'window.screen.height' );
    ($wwidth,$type)  = t::helper::safe_eval_in_page($mech, 'window.innerWidth' );
    ($wheight,$type) = t::helper::safe_eval_in_page($mech, 'window.innerHeight' );
    my $res = { width => $wwidth, height => $wheight, screenWidth => $width, screenHeight => $height };
    return $res;
}

t::helper::run_across_instances(\@instances, \&new_mech, 6, sub {
    my ($browser_instance, $mech) = @_;
    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    my $version = $mech->chrome_version;

    if( $version =~ /\b(\d+)\b/ and $1 < 62 ) {
        SKIP: {
            skip "Chrome before v62 needs unsupported parameters for the viewport", 6;
        };
        return
    } elsif( $version =~ /\b(\d+)\b/ and $1 < 63 ) {
        SKIP: {
            skip "Chrome v62 doesn't resize the screen for the viewport", 6;
        };
        return
    } elsif( $mech->chrome_version !~ /headless/i ) {
        SKIP: {
            skip "A headful browser can't fake its dimensions", 6;
        };
        return
    }

    t::helper::safe_get($mech, $server->url );

    my $start_size = get_viewport_size( $mech );

    my $huuge = {
            screenWidth => 4096,
            screenHeight => 1920,
            width => 1388,
            height => 792,
    };
    my $res;
    my $lives = eval {
        $res = $mech->viewport_size($huuge);
        1;
    };
    ok $lives, "We don't crash"
        or diag $@;

    # Now, ask the browser about its size:
    my $resized = get_viewport_size( $mech );
    is_deeply $resized, $huuge, "We resized the viewport"
        or diag Dumper $resized;

    # Restore device/screen settings
    $lives = eval {
        $res = $mech->viewport_size();
        1;
    };
    ok $lives, "We don't crash"
        or diag $@;

    $resized = get_viewport_size( $mech );
    is_deeply [@{$resized}{qw(screenWidth screenHeight)}], [@{$start_size}{qw(screenWidth screenHeight)}],
              "We restored the old screen metrics"
        or diag Dumper $resized;

    # Restore window settings
    $lives = eval {
        $res = $mech->viewport_size({ width => 0, height => 0 });
        $mech->sleep(0.1); # There is some weirdo race condition in Chrome here
        1;
    };
    ok $lives, "We don't crash"
        or diag $@;
    $resized = get_viewport_size( $mech );
    is_deeply [@{$resized}{qw(width height)}], [@{$start_size}{qw(width height)}],
              "We restored the old window metrics"
        or diag Dumper [$start_size,$resized];

    undef $mech;
});

$server->stop;
alarm(0);

