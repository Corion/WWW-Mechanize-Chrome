#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use JSON;
use lib '.';

use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $m = WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

#my $server = Test::HTTP::LocalServer->spawn(
#    #debug => 1,
#);

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my ($browser_instance, $mech) = @_;

    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 < 63 ) {
            skip "Chrome before v63 doesn't know about online/offline mode or can do throttling", 4;
        } elsif( $version =~ /\b(\d+)\.\d+\.(\d+)\b/ and $1 == 63 and $2 < 3239) {
            # https://bugs.chromium.org/p/chromium/issues/detail?id=728451
            skip "Chrome before v63.0.3239 doesn't know about online/offline mode or can do throttling", 4;
        } else {
            #$mech->get($server->url);
            $mech->get_local('50-click.html');

            my ($value,$type);
            ($value, $type) = $mech->eval_in_page('window.navigator.connection.effectiveType');
            #is( $value, '4g', "We are online");
            ($value, $type) = $mech->eval_in_page('window.navigator.onLine');
            is( $value, JSON::true, "We are online (.onLine)");

            $mech->emulateNetworkConditions(
                offline => JSON::true,
                latency => 0,
                downloadThroughput => 0,
                uploadThroughput => 0,
                #connectionType => 'none',
            );
            ($value, $type) = $mech->eval('navigator.connection.effectiveType');
            #is( $value, 'offline', "We are offline");
            ($value, $type) = $mech->eval_in_page('window.navigator.onLine');
            is( $value, JSON::false, "We are offline (.onLine)");

            my $res = $mech->get('https://google.de');
            ok !$res->is_success, "We can't fetch pages while offline";
            #$mech->eval_in_page(sprintf 'window.location="%s"', '49-mech-get-file.html');

            $mech->emulateNetworkConditions(
                offline => JSON::false,
            );
            ($value, $type) = $mech->eval('navigator.connection.effectiveType');
            #is( $value, '4g', "We are online again");
            ($value, $type) = $mech->eval_in_page('window.navigator.onLine');
            is( $value, JSON::true, "We are online (.onLine)");
        }
    }

    undef $mech;
});