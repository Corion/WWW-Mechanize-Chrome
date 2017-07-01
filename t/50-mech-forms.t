#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
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
    plan tests => 14*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 14, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('50-click.html');

    my $f = $mech->forms;
    is ref $f, 'ARRAY', "We got an arrayref of forms";

    is 0+@$f, 1, "We found one form";

    is $f->[0]->get_attribute('id'), 'foo', "We found the one form";

    my @f = $mech->forms;

    is 0+@f, 1, "We found one form";

    is $f[0]->get_attribute('id'), 'foo', "We found the one form";

    $mech->get_local('50-form2.html');

    $f = $mech->forms;
    is ref $f, 'ARRAY', "We got an arrayref of forms";

    is 0+@$f, 5, "We found five forms";

    is $f->[0]->get_attribute('id'), 'snd0', "We found the first form";
    is $f->[1]->get_attribute('id'), 'snd', "We found the second form";
    is $f->[2]->get_attribute('id'), 'snd2', "We found the third form";
    is $f->[3]->get_attribute('id'), 'snd3', "We found the fourth form";
    is $f->[4]->get_attribute('id'), 'snd4', "We found the fifth form";

    $mech->get_local('51-empty-page.html');
    @f = $mech->forms;

    is_deeply \@f, [], "We found no forms"
        or diag $mech->content;

    undef $mech;
});