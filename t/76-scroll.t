#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use Test::HTTP::LocalServer;

use lib '.';
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

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    $mech->autodie(1);
    $mech->allow('javascript' => 1);
    $mech->get_local('76-infinite-scroll.html');

    is ($mech->infinite_scroll, 1, 'Can scroll down and retrieve new content');
    is (scroll_to_bottom($mech), 0, 'Can scroll to end of infinite scroll'); 

});

sub scroll_to_bottom {
  my $self = shift;
  while ($self->infinite_scroll(2)) { 
  }
}


