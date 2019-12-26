#!perl
#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';

use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
our $testcount = 3;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
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

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    $mech->get($server->url);
    my $text;
    my $ok = eval {
        $text = $mech->text;
        1;
    };
    my $err = $@;
    is $ok, 1, "We lived";
    is $err, '', "No error";
    like $text, qr/Request headers/, "We fetch some text";
});
