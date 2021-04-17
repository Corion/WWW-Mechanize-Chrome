#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use File::Temp 'tempfile';
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

use lib '.';
use t::helper;

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $testcount = 3;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

my ($fh, $fn) = tempfile();
close $fh;

sub new_mech {
    # Just keep these to pass the parameters to new instances
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );

    WWW::Mechanize::Chrome->new(
    autodie => 0,
    startup_timeout => 4,
    headless => 1,
    json_log_file => $fn,
    @_,);
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_; # so we move references
    isa_ok $mech, 'WWW::Mechanize::Chrome';
    my $info = $mech->driver->createTarget()->get;
    my $targetId = $mech->driver->targetId; # this one should close once we discard it

    undef $mech;

    ok -f $fn, "JSON logfile exists";
    ok -s $fn, "We wrote something into the logfile";
});

unlink $fn;
