#!perl -w
use strict;
use Test::More;
use File::Basename;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);

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

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

use vars '$mech';

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 1, sub {
    my( $file, $mymech ) = splice @_; # so we move references

    use WWW::Mechanize::Chrome::DSL ();
    Object::Import->import( $mymech );
    
    get_local( '49-mech-get-file.html' );
    sleep 1;
    is title(), '49-mech-get-file.html', 'We opened the right page';
    #is ct(), 'text/html', "Content-Type is text/html";
    diag uri();

    undef $mech;
});