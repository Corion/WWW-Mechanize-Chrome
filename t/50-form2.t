#!perl -w
use strict;
use Test::More;
use Test::Deep;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 32*@instances;
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

t::helper::run_across_instances(\@instances, \&new_mech, 32, sub {
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
    ok $mech->current_form, "After setting form_id, We have a current form";
    $mech->sleep(1);
    is $mech->current_form->get_attribute('id'), 'snd2', "We can ask the form with get_attribute(id)";
    my $content = $mech->current_form->get_text;
    ok !!$content, "We got content from asking the current form with get_text";
    $mech->field('id', 99);
    pass "We survived setting the field 'id' to 99";
    my $current_form = $mech->current_form;
    ok !!$current_form, "We got a current form";
    my $objectId = $current_form->objectId;
    ok !!$objectId, "The form has an objectId '$objectId'";
    like $objectId, qr{injectedScriptId}, "The objectId matches /injectedScriptId/";
    $objectId = $current_form->objectId;
    is $@, '', "No error when retrieving objectId twice";
    ok !!$objectId, "The form still has an objectId '$objectId'";
    like $objectId, qr{injectedScriptId}, "The objectId still matches /injectedScriptId/";
    my $content2;
    #eval {
        $content2 = $current_form->get_text;
    #};
    is $@, '', "No error when retrieving form text";
    ok !!$content2, "We got content from (again) asking the current form with get_text";
    isnt $content2, $content, "we managed to change the form by setting the 'id' field";
    is $mech->xpath('.//*[@name="id"]',
        node => $mech->current_form,
        single => 1)->get_attribute('value'), 99,
        "We have set field 'id' to '99' in the correct form";

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
    $mech->field('comment', "Just another Phrome Hacker,");
    pass "We survived setting the field 'comment' to some JAPH";
    like $mech->xpath('.//textarea',
        node   => $mech->current_form,
        single => 1)->get_text, qr/Just another/,
        "We set textarea and verified it";

    $mech->get_local('50-form2.html');
    $mech->form_with_fields('quickcomment');
    ok $mech->current_form, "We can find a form by its contained select fields";
    $mech->field('quickcomment', 2);
    pass "We survived setting the field 'quickcomment' to 2";
    my @result = $mech->field('quickcomment');
    cmp_bag \@result, [2], "->field returned bag 2";
    # diag explain \@result;

    $mech->get_local('50-form2.html');
    $mech->form_with_fields('multic');
    ok $mech->current_form, "We can find a form by its contained multi-select fields";
    @result = $mech->field('multic');
    cmp_bag \@result, [2,2,3], "->field returned bag 2,2,3";
    # diag explain \@result;

    $mech->field('multic', [1,2]);
    pass "We survived setting the field 'multic' to 1,2";
    @result = $mech->field('multic');
    cmp_bag \@result, [1,1,2,2], "->field returned bag 1,1,2,2";
    # diag explain \@result;
});
