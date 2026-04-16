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
my $testcount = 18;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 90 : 30);

$mech->autodie(1);

t::helper::safe_get_local($mech, '50-tick.html');

my ($clicked,$type,$ok);

# Xpath
t::helper::safe_get_local($mech, '50-tick.html');
my $node = t::helper::safe_selector($mech, '#unchecked_1',single => 1);
ok ! $node->get_attribute('checked'), "#unchecked_1 is not checked";
note "Ticking #unchecked_1";
$node = t::helper::safe_tick($mech, $node);
ok $node->get_attribute('checked'), "#unchecked_1 is now checked";

t::helper::safe_get_local($mech, '50-tick.html');
$node = t::helper::safe_selector($mech, '#unchecked_1',single => 1);
ok ! $node->get_attribute('checked'), "#unchecked_1 is not checked";
note "Ticking unchecked index 3";
$node = t::helper::safe_tick($mech, 'unchecked',3);
ok ! t::helper::safe_selector($mech, '#unchecked_1',single => 1)->get_attribute('checked'), "#unchecked_1 is not checked";
ok $node->get_attribute('checked'),  "#unchecked_3 is now checked";

t::helper::safe_get_local($mech, '50-tick.html');
$node = t::helper::safe_selector($mech, '#unchecked_1',single => 1);
ok ! $node->get_attribute('checked'), "#unchecked_1 is not checked";
note "Ticking unchecked index 1";
$node = t::helper::safe_tick($mech, 'unchecked',1);
ok $node->get_attribute('checked'),  "#unchecked_1 is now checked";
ok ! t::helper::safe_selector($mech, '#unchecked_3',single => 1)->get_attribute('checked'), "#unchecked_3 is not checked";

# Now check not setting things
t::helper::safe_get_local($mech, '50-tick.html');
$node = t::helper::safe_selector($mech, '#unchecked_1',single => 1);
ok ! $node->get_attribute('checked'), "#unchecked_1 is not checked";
note "Ticking unchecked index 1 to 0";
$node = t::helper::safe_tick($mech, 'unchecked',1,0);
ok ! $node->get_attribute('checked'), "#unchecked_1 is not checked";
ok ! t::helper::safe_selector($mech, '#unchecked_3',single => 1)->get_attribute('checked'), "#unchecked_3 is not checked";

# Now check removing checkmarks
t::helper::safe_get_local($mech, '50-tick.html');
$node = t::helper::safe_selector($mech, '#prechecked_1',single => 1);
ok $node->get_attribute('checked'), "#prechecked_1 is checked";
note "Ticking prechecked index 1 to 0";
$node = t::helper::safe_tick($mech, 'prechecked',1,0);
ok ! $node->get_attribute('checked'), "#prechecked_1 is not checked";
ok t::helper::safe_selector($mech, '#prechecked_3',single => 1)->get_attribute('checked'), "#prechecked_3 is still checked";

# Now check removing checkmarks
t::helper::safe_get_local($mech, '50-tick.html');
my $node1 = t::helper::safe_selector($mech, '#prechecked_1',single => 1);
my $node3 = t::helper::safe_selector($mech, '#prechecked_3',single => 1);
ok $node1->get_attribute('checked'), "#prechecked_1 is checked";
ok $node3->get_attribute('checked'), "#prechecked_3 is checked";
note "Unticking prechecked index 3";
$node3 = t::helper::safe_untick($mech, 'prechecked',3);
ok t::helper::safe_selector($mech, '#prechecked_1',single => 1)->get_attribute('checked'), "#prechecked_1 is still checked";
ok ! $node3->get_attribute('checked'), "#prechecked_3 is not checked";

note "End of test sub for $browser_instance";
});

alarm(0);

