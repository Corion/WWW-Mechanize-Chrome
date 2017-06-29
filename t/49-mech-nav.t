#!perl
use warnings;
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc';
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
    plan tests => 3*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 3, sub {
    my( $file, $mech ) = splice @_; # so we move references

    $mech->get($server->url);
    
    $mech->click_button(number => 1);
    like( $mech->uri, qr/formsubmit/, 'Clicking on button by number' );
    my $last = $mech->uri;
    
    diag "Going back";
    $mech->back;
    is $mech->uri, $server->url, 'We went back';
    
    diag "Going forward";
    $mech->forward;
    is $mech->uri, $last, 'We went forward';
});