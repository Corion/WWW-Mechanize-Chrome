#!perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;
use Data::Dumper;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

Log::Log4perl->easy_init($ERROR);

use Test::More;

my $testcount = 2;
plan tests => $testcount * 2 * 2;

my $interactive_tests = ($ENV{LOGNAME} || '') eq 'corion'
                        and ($ENV{DISPLAY} or $^X =~ /mswin/i);

SKIP: for my $interactive (1,0) {

    if( $interactive and !$interactive_tests ) {
        skip "Skipping interactive tests", $testcount * 2 * 2;
    }

    for my $separate_session (0,1) {

        my $description = join ", ",
            ($interactive ? 'interactive' : 'headless'),
            ($separate_session ? 'separate session' : 'main session'),
            ;

        note $description;
        my $mech = WWW::Mechanize::Chrome->new(
            headless => !$interactive,
            separate_session => $separate_session,
            data_directory => '/home/corion/.config/chromium',
        );

        my @windows = map {
                $_->get
            } $mech->driver->getTargets->then(sub(@targets) {
            Future->wait_all(
                map {
                    $mech->transport->getWindowForTarget($_->{targetId})
                } @targets
            )
        })->get;

        my %window;
        $window{ $_->{windowId} } = 1
            for @windows;

        my $name;
        if( $separate_session ) {
            $name = "We only create one additional window for the session ($description)";
        } else {
            $name = "We create no additional window for reusing the session ($description)";
        };
        {
            local $TODO = "Headless reused sessions spawn an additional tab?"
                if( not $interactive and not $separate_session );
            is( scalar keys %window, 1+$separate_session,  $name );
        };

        # Check that we have the expected fixed cookie:
        # This requires a good setup on part of the test author
        # or maybe we just expect zero cookies in a separate session
        # and zero-or-more cookies in a plain session?!

        my $expected_count = $separate_session ? 0 : 1;

        my $cookies = $mech->cookie_jar;
        my $c = $cookies->get_cookies('https://perlmonks.com');
        delete $c->{'$Version'};
        is keys %{ $c }, $expected_count, "We have $expected_count cookies";
    }
}
