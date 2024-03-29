#!perl -w
use strict;
use stable 'postderef';
use Test::More;
use File::Basename;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $testcount = 1;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

my %args;
sub new_mech {
    # Just keep these to pass the parameters to new instances
    %args = @_;
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        autoclose => 0,
        %args,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_; # so we move references

    my $pid = $mech->{pid};
    undef $mech;

    my $alive = kill 0 => $pid;
    is $alive, 1, "The Chrome process stays alive if 'autoclose' is set to 0";

    if( $pid ) {
        WWW::Mechanize::Chrome->kill_child('SIGKILL', $pid, undef);
    };
});
