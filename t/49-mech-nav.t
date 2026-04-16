#!perl
use warnings;
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 5;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 5*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

my $server = t::helper->safe_server(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_; # so we move references
    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    t::helper::safe_get($mech, $server->url);

    t::helper::safe_click_button($mech, number => 1);
    like( $mech->uri, qr/formsubmit/, 'Clicking on button by number' );
    my $last = $mech->uri;

    t::helper::safe_back($mech);
    is $mech->uri, $server->url, 'We went back';

    t::helper::safe_forward($mech);

    is $mech->uri, $last, 'We went forward';

    my $version = $mech->chrome_version;
    SKIP: {
        #if( $version =~ /\b(\d+)\b/ and $1 < 66 ) {
            t::helper::safe_reload($mech);
            is $mech->uri, $last, 'We reloaded';
            t::helper::safe_reload($mech, ignoreCache => 1 );
            is $mech->uri, $last, 'We reloaded, ignoring the cache';
        #} else {
        #    skip "Chrome v66+ doesn't know how to reload without hanging in a dialog box", 1;
        #}
    };
});
$server->stop;
alarm(0);

