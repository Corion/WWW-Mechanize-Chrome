#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl ':easy';
use HTTP::Cookies;
use File::Basename 'dirname';
use Test::HTTP::LocalServer;
use Data::Dumper;

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 15;

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

my $server = Test::HTTP::LocalServer->spawn;

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    my $version = $mech->chrome_version;

    note "Fetching cookie jar";
    my $cookies = $mech->cookie_jar;
    isa_ok $cookies, 'HTTP::Cookies';

    if( $version =~ /\b(\d+)\b/ and ($1 >= 59 and $1 <= 62)) {
        SKIP: {
            skip "Chrome v$1 doesn't properly handle setting cookies...", $testcount-1;
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
            1,
            'mycookie' => 'tasty1',
            '/',
            'example.com',
            0,
            '',
            1,
            600,
            0
        );
        my $lived = eval {
            $cookies->load_jar( $other_jar, replace => 1 );
            1;
        };
        ok $lived, "We can load another cookie jar"
            or diag $@;
        $count = 0;
        my @c;
        $cookies->scan(sub{$count++; push @c, [@_];});
        is $count, 1, 'We replaced all the cookies with our single cookie from the jar'
            or diag Dumper \@c;

        $lived = eval {
            $cookies->load(dirname($0).'/CookiesOld');
            1;
        };
        ok $lived, "We can load cookies from file"
            or diag $@;

        $other_jar = HTTP::Cookies->new();
    #$self->SUPER::set_cookie( $version, $key, $val, $path, $domain, $port, $path_spec, $secure, $maxage, $discard );
        $other_jar->set_cookie(
            1,
            'mycookie' => 'tasty2',
            '/',
            $server->url->host_port,
            $server->url->port,
            #undef,
            '',
            0, # our test server only implements http
            600,
            0
        );
        $lived = eval {
            $cookies->load_jar( $other_jar, replace => 1 );
            1;
        };
        ok $lived, "We can load another cookie jar"
            or diag $@;
        $count = 0;
        @c = ();
        $cookies->scan(sub{$count++; push @c,[@_]});
        is $count, 1, 'We replaced all the cookies with our single cookie from the (manual) jar'
            or diag Dumper \@c;
        $mech->cookie_jar->load;
        $mech->get($server->url);
        like $mech->content, qr/\btasty2\b/, "Our cookie gets sent";
        $mech->cookie_jar->load;

        $count = 0;
        @c = ();
        $cookies->scan(sub{$count++; push @c,[@_]});
        cmp_ok $count, '>=', 3, "We keep the cookies our test server sends";

    }

    undef $mech;
});

undef $server;
