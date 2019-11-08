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
    plan tests => 9*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, \&new_mech, 9, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    $mech->autodie(1);

    $mech->get_local('50-click.html');
    $mech->allow('javascript' => 1);

    my ($clicked,$type,$ok);

    eval {
        ($clicked, $type) = $mech->eval_in_page('clicked');
        $ok = 1;
    };
    diag $@ if $@;

    if (! $clicked) {
        SKIP: { skip "Couldn't get at 'clicked'. Do you have a Javascript blocker?", 8; };
        return;
    };

    ok $clicked, "We found 'clicked'";

    # Xpath
    $mech->get_local('50-click.html');
    $mech->allow('javascript' => 1);
    $mech->follow_link( xpath => '//*[@id="a_link"]', synchronize=>0, );
    ($clicked,$type) = $mech->eval_in_page('clicked');
    is $clicked, 'a_link', "->follow_link() with an xpath selector works";

    # CSS
    $mech->get_local('50-click.html');
    $mech->allow('javascript' => 1);
    $mech->follow_link( selector => '#a_link', synchronize=>0, );
    ($clicked,$type) = $mech->eval_in_page('clicked');
    is $clicked, 'a_link', "->follow_link() with a CSS selector works";

    # Regex
    $mech->get_local('50-click.html');
    $mech->allow('javascript' => 1);
    $mech->follow_link( text_regex => qr/A link/, synchronize => 0 );
    ($clicked,$type) = $mech->eval_in_page('clicked');
    is $clicked, 'a_link', "->follow_link() with a RE works";

    # Non-existing link
    $mech->get_local('50-click.html');
    my $lives = eval { $mech->follow_link('foobar'); 1 };
    my $msg = $@;
    ok !$lives, "->follow_link() on non-existing parameter fails correctly";
    like $msg, qr/No elements found for Button with name 'foobar'/,
        "... with the right error message";

    # Non-existing link via CSS selector
    $mech->get_local('50-click.html');
    $lives = eval { $mech->follow_link({ selector => 'foobar' }); 1 };
    $msg = $@;
    ok !$lives, "->follow_link() on non-existing parameter fails correctly";
    like $msg, qr/No elements found for CSS selector 'foobar'/,
        "... with the right error message";
});