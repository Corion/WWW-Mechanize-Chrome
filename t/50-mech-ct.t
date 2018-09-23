#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use Test::HTTP::LocalServer;

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
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

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    $mech->get($server->url);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    is $mech->ct, 'text/html', "Content-type of text/html";
});

undef $server;
wait; # gobble up our child process status