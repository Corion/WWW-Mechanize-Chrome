#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use Test::HTTP::LocalServer;

use lib '.';
use t::helper;

# (re)set the log level
if (my $lv = $ENV{TEST_LOG_LEVEL}) {
    if( $lv eq 'trace' ) {
        Log::Log4perl->easy_init($TRACE)
    } elsif( $lv eq 'debug' ) {
        Log::Log4perl->easy_init($DEBUG)
    }
}

# What instances of Chrome will we try?
my $instance_port = 9222;
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
        #headless => 0,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 1, sub {
    my ($browser_instance, $mech) = @_;

    $mech->autodie(1);

    $mech->get_local('76-infinite-scroll.html');
    $mech->allow('javascript' => 1);

    is ($mech->infinite_scroll, 1, 'Can scroll down and retrieve new content');
    is (scroll_to_bottom($mech), 0, 'Can scroll down to end of infinite scroll'); 
});

sub scroll_to_bottom {
  my $self = shift;
  my $return_val;
  while ($self->infinite_scroll(2)) {

  }
}


