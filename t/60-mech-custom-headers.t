#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
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
    plan tests => 21*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        extra_headers => {
            'X-My-Initial-Header' => '1',
        },
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, \&new_mech, 21, sub {

    # See https://bugs.chromium.org/p/chromium/issues/detail?id=795336
    #     https://bugs.chromium.org/p/chromium/issues/detail?id=767683
    # for the gory details on when things stopped working
    # Chrome 63 and Chrome 64 are broken but Chrome 65 sends custom headers
    # again, but does not allow to update the Referer: header

    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    # First get a clean check without the changed headers
    my ($site,$estatus) = ($server->url,200);
    my $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    my $ua = "WWW::Mechanize::Chrome $0 $$";
    my $version = $mech->chrome_version;
    my $ref;
    if( $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ("$1.$2" >= 63.84)) {
        $ref = 'https://example.com/';
    } else {
        $ref = 'http://example.com/'; # earlier versions crash on https referrer ...
    };

    my @host;
    if( $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ("$1.$2" < 76.00)) {
        @host = (Host => 'www.example.com'); # later versions won't fetch a page with a "wrong" Host: header
    };

    $mech->add_header(
        'Referer' => $ref,
        'X-WWW-Mechanize-Chrome' => "$WWW::Mechanize::Chrome::VERSION",
        @host
    );

    $mech->agent( $ua );

    $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site"
        or diag $mech->content;
    # Now check for the changes
    my $headers = $mech->selector('#request_headers', single => 1)->get_attribute('innerText');
    {
        local $TODO = "Chrome v63+ doesn't send the Referer header..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 >= 62 or $2 >= 3239);
        like $headers, qr!^Referer: \Q$ref\E$!m, "We sent the correct Referer header";
    }
    like $headers, qr!^User-Agent: \Q$ua\E$!m, "We sent the correct User-Agent header";
    {
        local $TODO = "Chrome v63.0.84+ doesn't set custom headers..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 == 63 and $3 >= 84);
        like $headers, qr!^X-WWW-Mechanize-Chrome: \Q$WWW::Mechanize::Chrome::VERSION\E$!m, "We can add completely custom headers";
    }
    {
        local $TODO = "Chrome v63.0.84+ doesn't send the Host header..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 == 63 and $3 >= 84);
        like $headers, qr!^X-My-Initial-Header: 1$!m, "We can add completely custom headers at start";
        local $TODO = "Chrome v76+ doesn't set (or send) the Host header anymore..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 >= 76);
        like $headers, qr!^Host: www.example.com\s*$!m, "We can add custom Host: headers";
    }
    $mech->submit_form; # retrieve the JS window.navigator.userAgent value
    is $mech->value('navigator'), $ua, "JS window.navigator.userAgent gets set as well";
    # diag $mech->content;

    $mech->delete_header(
        'X-WWW-Mechanize-Chrome',
    );
    $mech->add_header(
        'X-Another-Header' => 'Oh yes',
    );

    $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    # Now check for the changes
    $headers = $mech->selector('#request_headers', single => 1)->get_attribute('innerText');
    {
        local $TODO = "Chrome v63+ doesn't send the Referer header..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\b/ and ($1 >= 62 or $2 >= 3239);
        like $headers, qr!^Referer: \Q$ref\E$!m, "We sent the correct Referer header";
    };
    like $headers, qr!^User-Agent: \Q$ua\E$!m, "We sent the correct User-Agent header";
    unlike $headers, qr!^X-WWW-Mechanize-Chrome: !m, "We can delete completely custom headers";
    {
        local $TODO = "Chrome v63.0.84+ doesn't set custom headers..."
            if $version =~ /\b(\d+)\.\d+\.(\d+)\.(\d+)\b/ and ($1 == 63 and $3 >= 84);
        like $headers, qr!^X-Another-Header: !m, "We can add other headers and still keep the current header settings";
    };

    # Now check that the custom headers go away if we uninstall them
    $mech->reset_headers();

    $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    # Now check for the changes
    $headers = $mech->selector('#request_headers', single => 1)->get_attribute('innerText');
    #diag $headers;
    # Chrome doesn't reset the Referer header...
    #unlike $headers, qr!^Referer: \Q$ref\E$!m, "We restored the old Referer header";
    # ->reset_headers does not restore the UA here...
    #unlike $headers, qr!^User-Agent: \Q$ua\E$!m, "We restored the old User-Agent header";
    unlike $headers, qr!^X-WWW-Mechanize-Chrome: \Q$WWW::Mechanize::Chrome::VERSION\E$!m, "We can remove completely custom headers";
    unlike $headers, qr!^X-Another-Header: !m, "We can remove other headers ";
    # diag $mech->content;
});

$server->kill;
undef $server;
