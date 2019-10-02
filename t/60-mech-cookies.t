#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl ':easy';
use lib '.';
use t::helper;
use Test::HTTP::LocalServer;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    my $version = $mech->chrome_version;

    $mech->get( $server->url );

    note "Fetching cookie jar";
    my $cookies = $mech->cookie_jar;
    isa_ok $cookies, 'HTTP::Cookies';

    if( $version =~ /\b(\d+)\b/ and ($1 >= 59 and $1 <= 61)) {
        SKIP: {
            skip "Chrome v$1 doesn't properly handle setting cookies...", 1;
        };
    } else {

        $cookies->set_cookie(undef, 'foo','bar','/','localhost', undef, undef, JSON::true, time+10, undef);

        # Count how many cookies we get as a test.
        my $count = 0;
        $cookies->scan(sub{$count++; });
        ok $count > 0, 'We found at least one cookie';
    }

    undef $mech;
});
