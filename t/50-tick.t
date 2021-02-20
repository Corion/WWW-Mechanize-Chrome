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

$mech->autodie(1);

$mech->get_local('50-tick.html');

my ($clicked,$type,$ok);

# Xpath
$mech->get_local('50-tick.html');
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked";
$mech->tick('#unchecked_1');
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),'checked', "#unchecked_1 is now checked";

$mech->get_local('50-tick.html');
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked";
$mech->tick('unchecked',3);
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked"
    or diag $mech->selector('#unchecked_1',single => 1)->get_attribute('checked');
is $mech->selector('#unchecked_3',single => 1)->get_attribute('checked'),'checked',  "#unchecked_3 is now checked"
    or diag $mech->selector('#unchecked_3',single => 1)->get_attribute('checked');

$mech->get_local('50-tick.html');
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked";
$mech->tick('unchecked',1);
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),'checked',  "#unchecked_1 is now checked";
is $mech->selector('#unchecked_3',single => 1)->get_attribute('checked'),0, "#unchecked_3 is not checked";

# Now check not setting things
$mech->get_local('50-tick.html');
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked";
$mech->tick('unchecked',1,0);
is $mech->selector('#unchecked_1',single => 1)->get_attribute('checked'),0, "#unchecked_1 is not checked";
is $mech->selector('#unchecked_3',single => 1)->get_attribute('checked'),0, "#unchecked_3 is not checked";

# Now check removing checkmarks
$mech->get_local('50-tick.html');
is $mech->selector('#prechecked_1',single => 1)->get_attribute('checked'),'checked', "#prechecked_1 is checked";
$mech->tick('prechecked',1,0);
is $mech->selector('#prechecked_1',single => 1)->get_attribute('checked'),0, "#prechecked_1 is not checked";
is $mech->selector('#prechecked_3',single => 1)->get_attribute('checked'),'checked', "#prechecked_3 is still checked";

# Now check removing checkmarks
$mech->get_local('50-tick.html');
is $mech->selector('#prechecked_1',single => 1)->get_attribute('checked'),'checked', "#prechecked_1 is checked";
is $mech->selector('#prechecked_3',single => 1)->get_attribute('checked'),'checked', "#prechecked_3 is checked";
$mech->untick('prechecked',3);
is $mech->selector('#prechecked_1',single => 1)->get_attribute('checked'),'checked', "#prechecked_1 is still checked";
is $mech->selector('#prechecked_3',single => 1)->get_attribute('checked'),0, "#prechecked_3 is not checked";

});
