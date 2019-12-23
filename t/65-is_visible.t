#!perl
use strict;
use warnings;
use Test::More;
use WWW::Mechanize::Chrome;

use Cwd;
use URI;
use URI::file;
use File::Basename;
use File::Spec;
use File::Temp 'tempdir';
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# A parallelization hack can prefill @files already with other files
# see t/65-is_visible-2.t
our @files;
if( !@files) {
    @files = qw<
        65-is_visible_class.html
        65-is_visible_text.html
        65-is_visible_hidden.html
    >;
};

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => (12*@files+5)*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 12*@files+5, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    # Check that we can execute JS
    $mech->get_local($files[0]);
    $mech->allow('javascript' => 1);
    my ($triggered,$type,$ok);
    eval {
        ($triggered, $type) = $mech->eval_in_page('timer');
        $ok = 1;
    };
    if (! $triggered) {
        SKIP: {
            skip("Couldn't get at 'timer'. Do you have a Javascript blocker?", 12*@files +5);
        };
        return;
    };

    # Check that we can trigger the timeout
    for my $file ($files[0]) {
        $mech->get_local($file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        ok $mech->is_visible(selector => '#before'), "The element is visible";
        my $finished = eval {
            $mech->wait_until_invisible(selector => '#before', timeout => 1);
            1;
        };
        is $finished, undef, "We got an exception";
        like $@, qr/Timeout/, "We got a timeout error message";
    };

    for my $file (@files) {
        $mech->get_local($file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        my ($timer,$type) = $mech->eval_in_page('timer');
        #(my ($window),$type) = $mech->eval_in_page('window');
        #$window = $mech->tab->{linkedBrowser}->{contentWindow};

        ok $mech->is_visible(selector => 'body'), "We can see the body";

        if(! ok !$mech->is_visible(selector => '#standby'), "We can't see #standby") {
            my $standby = $mech->by_id('standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        ok !$mech->is_visible(selector => '.status', any => 1), "We can't see .status even though there exist multiple such elements";
        $mech->click({ selector => '#start', synchronize => 0 });

        my $timeout = time+2;
        while( time < $timeout and !$mech->is_visible(selector => '#standby')) {
            $mech->sleep(0.1);
        };

        ok $mech->is_visible(selector => '#standby'), "We can see #standby";
        my $ok = eval {
            $mech->wait_until_invisible(selector => '#standby', timeout => $timer+2);
            1;
        };
        is $ok, 1, "No timeout" or diag $@;
        if(! ok( !$mech->is_visible(selector => '#standby'), "The #standby is invisible")) {
            my $standby = $mech->by_id('standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };

        # Now test with plain text
        $mech->get_local($file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        ($timer,$type) = $mech->eval_in_page('timer');

        if(! ok( !$mech->is_visible(xpath => '//*[contains(text(),"stand by")]'), "We can't see the standby message (via its text)")) {
            my $standby = $mech->by_id('standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };

        $mech->click({ selector => '#start', synchronize => 0 });

        # Busy-wait
        $timeout = time+2;
        while( time < $timeout and !$mech->is_visible(xpath => '//*[contains(text(),"stand by")]')) {
            $mech->sleep(0.1);
        };

        if(! ok $mech->is_visible(xpath => '//*[contains(text(),"stand by")]'), "We can see the standby message (via its text)") {
            my $standby = $mech->by_id('standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        $ok = eval {
            # This needs to re-query every time as the text changes!!
            $mech->wait_until_invisible(xpath => '//*[contains(text(),"stand by")]', timeout => $timer+2);
            1;
        };
        if(! is $ok, 1, "No timeout") {
            diag $@;
            for ($mech->xpath('//*[contains(text(),"stand by")]')) {
                diag $_->{tagName}, $_->{innerHTML};
            };
            my $standby = $mech->xpath('//*[contains(text(),"stand by")]', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        ok !$mech->is_visible(selector => '#standby'), "The #standby is invisible";
    };
});
