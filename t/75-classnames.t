#!perl -w
use strict;
use Test::More;
use File::Basename;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib 'inc', '../inc', '.';
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
    plan tests => 1*@instances;
};

my %args;
sub new_mech {
    # Just keep these to pass the parameters to new instances
    if( ! keys %args ) {
        %args = @_;
    };
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        %args,
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 1, sub {
    my( $file, $mech ) = splice @_; # so we move references

	$mech->get_local('test-input-with-class.html');

	my $lives = eval {
		$mech->field('username', 'foobar');
		1
	};
	ok $lives 
	    or diag $@;
})