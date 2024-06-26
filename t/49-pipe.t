#!perl

use warnings;
use strict;
use stable 'postderef';
use Test::More;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use Test::HTTP::LocalServer;

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my @instances = t::helper::browser_instances();
my $testcount = 3;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} elsif ( $^O =~ /mswin/i ) {
    plan skip_all => "Pipes are currently unsupported on $^O";
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '72.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        @_,
        pipe    => 1,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
);

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = splice @_;

    $mech->get($server->url);
    pass "We launch Chrome and control it via two filehandles";

    my $pids = $mech->{pid};

    like $mech->title, qr/^WWW::Mechanize::Firefox test page$/, "Retrieving the title works";
    undef $mech;

    my $alive = kill( 0 => $pids->@*);
    is $alive, 0, "The chrome process $pids->@* was removed";
});

$server->stop;
