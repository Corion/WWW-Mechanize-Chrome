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

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 4, sub {
    my( $file, $mech ) = splice @_; # so we move references

    $mech->get($server->url);

    $mech->click_button(number => 1);
    like( $mech->uri, qr/formsubmit/, 'Clicking on button by number' );
    my $last = $mech->uri;

    $mech->back;
    is $mech->uri, $server->url, 'We went back';

    $mech->forward;

    is $mech->uri, $last, 'We went forward';

    my $version = $mech->chrome_version;
    SKIP: {
        #if( $version =~ /\b(\d+)\b/ and $1 < 66 ) {
            $mech->reload;
            is $mech->uri, $last, 'We reloaded';
        #} else {
        #    skip "Chrome v66+ doesn't know how to reload without hanging in a dialog box", 1;
        #}
    };
});
$server->kill;
undef $server;
