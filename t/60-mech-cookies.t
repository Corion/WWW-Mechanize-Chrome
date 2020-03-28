#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl ':easy';
use lib '.';
use t::helper;
use HTTP::Cookies;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 10*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    my $version = $mech->chrome_version;

    note "Fetching cookie jar";
    my $cookies = $mech->cookie_jar;
    isa_ok $cookies, 'HTTP::Cookies';

    if( $version =~ /\b(\d+)\b/ and ($1 >= 59 and $1 <= 61)) {
        SKIP: {
            skip "Chrome v$1 doesn't properly handle setting cookies...", 1;
        };
    } else {

        for my $cookie_val (1, JSON::true, JSON::false, 0, '', undef) {
            my $lived = eval {
                $cookies->set_cookie(undef, 'foo','bar','/','localhost', undef, undef, $cookie_val, time+10, undef);
                1;
            };
            is $lived, 1, sprintf "We can use %s as a value for 'secure'", defined $cookie_val ? "'$cookie_val'" : "undef"
                or diag $@;
        };

        # Count how many cookies we get as a test.
        my $count = 0;
        $cookies->scan(sub{$count++; });
        ok $count > 0, 'We found at least one cookie';

        my $other_jar = HTTP::Cookies->new();
        $other_jar->set_cookie(
            42,
            'mycookie' => 'tasty',
            '/',
            'example.com',
            0,
            '',
            1,
            time+600,
            0
        );
        my $lived = eval {
            $cookies->load_jar( $other_jar, replace => 1 );
            1;
        };
        ok $lived, "We can load another cookie jar"
            or diag $@;
        $count = 0;
        $cookies->scan(sub{$count++; });
        is $count, 1, 'We replaced all the cookies with our single cookie from the jar';
    }

    undef $mech;
});
