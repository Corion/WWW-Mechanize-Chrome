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

my $transport = WWW::Mechanize::Chrome->_preferred_transport({});

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit

} elsif( $transport =~ /::Pipe::/ ) {
    plan skip_all => "Pipe transport makes no sense for this test";
    exit

} else {
    plan tests => $test_count*@instances;
};

# Launch our Chrome instance separately:
my ($existing_mech, $instance_host, $instance_port);
my $expected_location = "data:text/html,Test-$$";

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
    my(%args) = @_;
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );

    $existing_mech = WWW::Mechanize::Chrome->new(
        @_,
        autodie => 1,
        headless => 1,
        connection_style => 'websocket',
    );

    $existing_mech->get($expected_location);
    #my $existing_mech;
    #my $instance_port = 9222;

    $instance_port = $existing_mech->{ port };
    $instance_host = $existing_mech->{ host };
    note "Instance communicates on port $instance_host:$instance_port";

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
    is $browser_launched, 1, "We didn't spawn a second process";
    is $mech->{pid}, undef, "We have no process to kill";

    note $mech->chrome_version;
    note $existing_mech->chrome_version;

    my $location = $mech->uri;
    is $location, $expected_location, "We connect to the same tab";
    note $mech->title;
    undef $mech;

    undef $existing_mech;

    $browser_launched = 0;
});

undef $existing_mech;

$server->stop;
