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

    t::helper::set_watchdog($t::helper::is_slow ? 90 : 12);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    # Check that we can execute JS
    t::helper::safe_get_local($mech, $files[0]);
    $mech->allow('javascript' => 1);
    my ($triggered,$type,$ok);
    eval {
        ($triggered, $type) = t::helper::safe_eval_in_page($mech, 'timer');
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
        t::helper::safe_get_local($mech, $file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        ok t::helper::safe_is_visible($mech, selector => '#before'), "The element is visible";
        my $finished = eval {
            t::helper::safe_wait_until_invisible($mech, selector => '#before', timeout => ($t::helper::is_slow ? 4 : 1));
            1;
        };
        is $finished, undef, "We got an exception";
        like $@, qr/Timeout/, "We got a timeout error message";
    };

    for my $file (@files) {
        t::helper::safe_get_local($mech, $file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        my ($timer,$type) = t::helper::safe_eval_in_page($mech, 'timer');
        #(my ($window),$type) = $mech->eval_in_page('window');
        #$window = $mech->tab->{linkedBrowser}->{contentWindow};

        ok t::helper::safe_is_visible($mech, selector => 'body'), "We can see the body";

        if(! ok !t::helper::safe_is_visible($mech, selector => '#standby'), "We can't see #standby") {
            my $standby = t::helper::safe_by_id($mech, 'standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        ok !t::helper::safe_is_visible($mech, selector => '.status', any => 1), "We can't see .status even though there exist multiple such elements";
        t::helper::safe_click($mech, { selector => '#start', synchronize => 0 });

        t::helper::safe_wait_until_visible($mech, selector => '#standby',
            timeout => ($t::helper::is_slow ? 10 : 6),
            max_wait => ($t::helper::is_slow ? 10 : 6)
        );

        ok t::helper::safe_is_visible($mech, selector => '#standby'), "We can see #standby";
        my $ok = eval {
            t::helper::safe_wait_until_invisible($mech, selector => '#standby', timeout => $timer+2);
            1;
        };
        is $ok, 1, "No timeout" or diag $@;
        if(! ok( !t::helper::safe_is_visible($mech, selector => '#standby'), "The #standby is invisible")) {
            my $standby = t::helper::safe_by_id($mech, 'standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };

        # Now test with plain text
        t::helper::safe_get_local($mech, $file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        ($timer,$type) = t::helper::safe_eval_in_page($mech, 'timer');

        if(! ok( !t::helper::safe_is_visible($mech, xpath => '//*[contains(text(),"stand by")]'), "We can't see the standby message (via its text)")) {
            my $standby = t::helper::safe_by_id($mech, 'standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };

        t::helper::safe_click($mech, { selector => '#start', synchronize => 0 });

        # Busy-wait
        t::helper::safe_wait_until_visible($mech, xpath => '//*[contains(text(),"stand by")]',
            timeout => ($t::helper::is_slow ? 10 : 6),
            max_wait => ($t::helper::is_slow ? 10 : 6)
        );

        if(! ok t::helper::safe_is_visible($mech, xpath => '//*[contains(text(),"stand by")]'), "We can see the standby message (via its text)") {
            my $standby = t::helper::safe_by_id($mech, 'standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        $ok = eval {
            # This needs to re-query every time as the text changes!!
            t::helper::safe_wait_until_invisible($mech, xpath => '//*[contains(text(),"stand by")]', timeout => $timer+2);
            1;
        };
        if(! is $ok, 1, "No timeout") {
            diag $@;
            for (t::helper::safe_xpath($mech, '//*[contains(text(),"stand by")]')) {
                diag $_->{tagName}, $_->{innerHTML};
            };
            my $standby = t::helper::safe_xpath($mech, '//*[contains(text(),"stand by")]', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        ok !t::helper::safe_is_visible($mech, selector => '#standby'), "The #standby is invisible";
    };

    note "End of test sub for $browser_instance";
});

alarm(0);
