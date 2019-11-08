#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use Test::HTTP::LocalServer;
#use Mojolicious;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 6*@instances;
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

t::helper::run_across_instances(\@instances, \&new_mech, 6, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my ($site,$estatus) = ($server->url,200);
    my $res = $mech->get($server->redirect(''));
    isa_ok $res, 'HTTP::Response', "Response";

    is $mech->uri, $site, "Navigated to $site";

    is $res->code, $estatus, "GETting $site returns HTTP code $estatus from response"
        or diag $mech->content;

    is $mech->status, $estatus, "GETting $site returns HTTP status $estatus from mech"
        or diag $mech->content;

    ok $mech->success, 'We consider this response successful';
});

undef $server;
wait; # gobble up our child process status
