#!perl -w
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
my $testcount = 9;

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

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my ($site,$estatus) = ($server->url,200);

    my $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    is $res->code, $estatus, "GETting $site returns HTTP code $estatus from response"
        or diag $mech->content;

    is $mech->status, $estatus, "GETting $site returns HTTP status $estatus from mech"
        or diag $mech->content;

    ok $mech->success, 'We consider this response successful';

    # Check that we can GET a binary file and see its content for download
    note my $url = $server->local('blank.jpg');
    $res = $mech->get($url);
    isa_ok $res, 'HTTP::Response', "We get a response for a direct image URL";
    is $res->code, $estatus, "GETting image returns 200"
        or diag $mech->content;

    #like $mech->content, qr/^<html/ms, "We have automatic HTML framing the image in the browser";
    $mech->sleep(0.1); # we need to give the response body time to arrive :(
    like $res->decoded_content, qr/^\xff\xd8\xff.*?JFIF/ms, "We have an image in the response";
});

$server->stop;
