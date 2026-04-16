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
my $testcount = 18;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $m = WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
    $m
};
t::helper::run_across_instances(\@instances, \&new_mech, 17, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my $res = t::helper::safe_get_local($mech, '50-click.html');
    ok $res->is_success, "We retrieved 50-click.html";

    note "Calling forms() in scalar context";
    my $f = $mech->forms;
    is ref $f, 'ARRAY', "We got an arrayref of forms";

    is 0+@$f, 1, "We found one form";

    is $f->[0]->get_attribute('id'), 'foo', "We found the one form";

    note "Calling forms() in list context";
    my @f = $mech->forms;

    is 0+@f, 1, "We found one form";

    is $f[0]->get_attribute('id'), 'foo', "We found the one form";

    note "Calling forms() on a page with multiple forms";
    t::helper::safe_get_local($mech, '50-form2.html');
    ok $mech->success, "We retrieved 50-form2.html";

    $f = $mech->forms;

    is ref $f, 'ARRAY', "We got an arrayref of forms";

    is 0+@$f, 7, "We found seven forms";

    is $f->[0]->get_attribute('id'), 'snd0', "We found the first form";
    is $f->[1]->get_attribute('id'), 'snd', "We found the second form";
    is $f->[2]->get_attribute('id'), 'snd2', "We found the third form";
    is $f->[3]->get_attribute('id'), 'snd3', "We found the fourth form";
    is $f->[4]->get_attribute('id'), 'snd4', "We found the fifth form";
    is $f->[5]->get_attribute('id'), 'snd5', "We found the sixth form";
    is $f->[6]->get_attribute('id'), 'samename', "We found the seventh form";

    note "Navigating to empty page";
    t::helper::safe_get_local($mech, '51-empty-page.html');
    note "Calling forms() on empty page";
    @f = $mech->forms;

    is_deeply \@f, [], "We found no forms"
        or diag $mech->content;

    undef $f;
    undef @f;
    undef $mech;

    note "End of test sub for $browser_instance";
});

alarm(0);
