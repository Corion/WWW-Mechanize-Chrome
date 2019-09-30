#!perl

use warnings;
use strict;
use Test::More;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use Test::HTTP::LocalServer;

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my @instances = t::helper::browser_instances();
if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        @_,
        pipe    => 1,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
);

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = splice @_;

    $mech->get($server->url);
    pass "We launch Chrome and control it via two filehandles";

    like $mech->title, qr/^WWW::Mechanize::Firefox test page$/, "Retrieving the title works";
    undef $mech;
});

$server->kill;
undef $server;
#wait; # gobble up our child process status
