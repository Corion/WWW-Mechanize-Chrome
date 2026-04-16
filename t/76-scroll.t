#!perl -w
use strict;
use Test::More;
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
} else {
    plan tests => 3*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 3, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    $mech->autodie(1);
    $mech->allow('javascript' => 1);
    t::helper::safe_get_local($mech, '76-infinite-scroll.html');

    is (t::helper::safe_eval_in_page($mech, 'scroll_count'), 0, 'Initial scroll count');
    is (t::helper::safe_infinite_scroll($mech, 1), 1, 'Can scroll down and retrieve new content');
    is (scroll_to_bottom($mech), 0, 'Can scroll to end of infinite scroll');

    note "End of test sub for $browser_instance";
});

alarm(0);

sub scroll_to_bottom {
  my $self = shift;
  while (t::helper::safe_infinite_scroll($self, 2)) {
  }
}


