#!perl -w
use strict;
use Test::More;
use File::Basename;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);

use lib '.';
use Test::HTTP::LocalServer;

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
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

our $mech;

my $imported;

t::helper::run_across_instances(\@instances, \&new_mech, 1, sub {
    my( $file, $mymech ) = splice @_; # so we move references
    $mech = $mymech;
    undef $mymech;

    if( ! $imported++ ) {
        use WWW::Mechanize::Chrome::DSL ();
        Object::Import->import( \$mech, deref => 1 );
    };

    get_local( '49-mech-get-file.html' );
    is title(), '49-mech-get-file.html', 'We opened the right page';
    is ct(), 'text/html', "Content-Type is text/html";

    $mech->DESTROY;

    undef $mech;
});