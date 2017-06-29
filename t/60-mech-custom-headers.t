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
    plan tests => 20*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 20, sub {

    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    # First get a clean check without the changed headers
    my ($site,$estatus) = ($server->url,200);
    my $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    my $ua = "WWW::Mechanize::Chrome $0 $$";
    my $ref = 'http://example.com/';
    $mech->add_header(
        'Referer' => $ref,
        'X-WWW-Mechanize-Chrome' => "$WWW::Mechanize::Chrome::VERSION",
        'Host' => 'www.example.com',
    );

    $mech->agent( $ua );

    $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";
    # Now check for the changes
    my $headers = $mech->selector('#request_headers', single => 1)->get_attribute('innerText');
    like $headers, qr!^Referer: \Q$ref\E$!m, "We sent the correct Referer header";
    like $headers, qr!^User-Agent: \Q$ua\E$!m, "We sent the correct User-Agent header";
    like $headers, qr!^X-WWW-Mechanize-Chrome: \Q$WWW::Mechanize::Chrome::VERSION\E$!m, "We can add completely custom headers";
    like $headers, qr!^Host: www.example.com\s*$!m, "We can add custom Host: headers";
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
    like $headers, qr!^Referer: \Q$ref\E$!m, "We sent the correct Referer header";
    like $headers, qr!^User-Agent: \Q$ua\E$!m, "We sent the correct User-Agent header";
    unlike $headers, qr!^X-WWW-Mechanize-PhantomJS: !m, "We can delete completely custom headers";
    like $headers, qr!^X-Another-Header: !m, "We can add other headers and still keep the current header settings";
    # diag $mech->content;

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

undef $server;
wait; # gobble up our child process status