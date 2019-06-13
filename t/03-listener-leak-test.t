#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Test::HTTP::LocalServer;
use Data::Dumper;
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();
my $testcount = (@instances*1);
if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount;
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

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    my ($site,$estatus) = ($server->url,200);

    my $res = $mech->get($site);

    for( 1..10 ) {
        my @input = $mech->xpath('//input[@name="q"]');
    };
    is scalar @{ $mech->driver->listener->{'DOM.setChildNodes'} }, 0, "We don't accumulate listeners";
});