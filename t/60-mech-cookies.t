#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl ':easy';
use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 8*@instances;
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
    }

    undef $mech;
});
