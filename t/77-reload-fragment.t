#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;

use strict;
use Test::More;
use Cwd;
use URI;
use URI::file;
use File::Basename;
use File::Spec;
use File::Temp 'tempdir';
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

my $url = $server->url;
my @urls = (
    "$url#1",
    "$url#2",
);

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;
    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and ($1 == 64 or $1 == 59)) {
            skip "Chrome 64 doesn't handle self-navigating well", 2;
        } else {
            for my $url (@urls) {
                $mech->get( $url );
                pass "We retrieved $url";
            };
        };
    };
});
