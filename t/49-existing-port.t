#!perl

use warnings;
use strict;
use Test::More;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my @instances = t::helper::browser_instances();
my $test_count = 4;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $test_count*@instances;
};

# Launch our Chrome instance separately:
my $existing_mech = WWW::Mechanize::Chrome->new(
    autodie => 1,
    headless => 1,
    connection_style => 'websocket',

    # Using localhost or ::1 is flakey - we require IPv4 it seems
    #host             => 'localhost',
    #host             => '::1',


    #port             => 9222,
    #port             => 0,
);
my $expected_location = "data:text/html,Test-$$";
$existing_mech->get($expected_location);
#my $existing_mech;
#my $instance_port = 9222;

#my $instance_port = $existing_mech->target->transport->port;
my $instance_port = $existing_mech->{ port };
my $instance_host = $existing_mech->{ host };
note "Instance communicates on port $instance_host:$instance_port";

my $browser_launched = 0;
my $org = \&WWW::Mechanize::Chrome::_spawn_new_chrome_instance;
{
    no warnings 'redefine';
    *WWW::Mechanize::Chrome::_spawn_new_chrome_instance = sub {
        $browser_launched++;
        goto &$org;
    };
}

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        port    => $instance_port,
        host    => $instance_host,
        # tab     => 'current',
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, $test_count, sub {
    my ($browser_instance, $mech) = splice @_;

    pass "We can connect to port $instance_port";
    is $browser_launched, 0, "We didn't spawn a new process";
    is $mech->{pid}, undef, "We have no process to kill";
    my $location = $mech->uri;
    is $location, $expected_location, "We connect to the same tab";
    note $mech->title;
    undef $mech;

    $browser_launched = 0;
});

undef $existing_mech;

$server->stop;
