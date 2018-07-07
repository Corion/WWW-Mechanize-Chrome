#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use Test::HTTP::LocalServer;
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

my $url = $server->url;

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        start_url => $url,
        @_,
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    is $mech->uri, $url, "We moved to the start URL instead of about:blank";
});