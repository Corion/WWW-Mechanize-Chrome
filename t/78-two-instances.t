#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use Data::Dumper;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} elsif(! eval {
    require Test::Memory::Cycle;
    Test::Memory::Cycle->import;
    1;
}) {
    plan skip_all => "$@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        #autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my ($browser_instance, $mech) = @_;

    memory_cycle_ok( $mech, "A fresh mechanize doesn't have a cycle" );

    my $mech2 = new_mech( headless => 1 );
    ok $mech2, "We replaced the first with a second Chrome instance";
    memory_cycle_ok( $mech2, "A fresh mechanize doesn't have a cycle" );

    undef $mech;
    $mech = new_mech( headless => 1 );
    ok $mech, "We replaced the first with a third Chrome instance";
});
