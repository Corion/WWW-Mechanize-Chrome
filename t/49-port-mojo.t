#!perl

use warnings;
use strict;
use Test::More;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
#Log::Log4perl->easy_init($TRACE);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
#my $instance_port = 9222;
my $instance_port;
my @instances = t::helper::browser_instances();

my $have_mojolicious = eval {
    require Mojolicious;
    1
};
my $err = $@;
if( ! $have_mojolicious ) {
    plan skip_all => "Couldn't load Mojolicious: $err";
    exit

} elsif (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 1*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 1, sub {
    my ($browser_instance, $mech) = splice @_;

    $mech->get($server->url);
    pass "We can connect to port $instance_port";
    undef $mech;
});

undef $server;
#wait; # gobble up our child process status