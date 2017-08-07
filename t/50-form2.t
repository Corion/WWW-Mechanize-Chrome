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
    plan tests => 13*@instances;
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

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 13, sub {
    my ($browser_instance, $mech) = @_;

    $mech->get_local('50-form2.html');
    ok $mech->current_form, "At start, we have a current form";
    $mech->form_number(2);
    my $button = $mech->selector('#btn_ok', single => 1);
    isa_ok $button, 'WWW::Mechanize::Chrome::Node', "The button image";
    ok $mech->submit, 'Sent the page';
    ok $mech->current_form, "After a submit, we have a current form";

    $mech->get_local('50-form2.html');
    $mech->form_id('snd2');
    ok $mech->current_form, "We can find a form by its id";
    is $mech->current_form->get_attribute('id'), 'snd2', "We can find a form by its id";
    $mech->field('id', 99);
    is $mech->xpath('.//*[@name="id"]',
        node => $mech->current_form, 
        single => 1)->get_attribute('value'), 99,
        "We set values in the correct form";

    $mech->get_local('50-form2.html');
    $mech->form_with_fields('r1','r2');
    ok $mech->current_form, "We can find a form by its contained input fields";

    $mech->get_local('50-form2.html');
    $mech->form_name('snd');
    ok $mech->current_form, "We can find a form by its name";
    is $mech->current_form->get_attribute('name'), 'snd', "We can find a form by its name";

    $mech->get_local('50-form2.html');
    ok $mech->current_form, "On a new ->get, we have a current form";

    $mech->get_local('50-form2.html');
    $mech->form_with_fields('comment');
    ok $mech->current_form, "We can find a form by its contained textarea fields";

    $mech->get_local('50-form2.html');
    $mech->form_with_fields('quickcomment');
    ok $mech->current_form, "We can find a form by its contained select fields";
});
