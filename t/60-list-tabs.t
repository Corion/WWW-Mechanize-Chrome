#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use Test::HTTP::LocalServer;
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 4;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    my( %args ) = @_;
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $v = WWW::Mechanize::Chrome->chrome_version(%args);
    $v =~ m!/(\d+)\.(\d+)\.(\d+)\.(\d+)$!
        or die "Couldn't find Chrome version info from '$v'";

    my $connection_style = WWW::Mechanize::Chrome->connection_style(\%args);
    if( $1 <= 71 ) { # Chrome before v72 doesn't speak pipes
        if( $connection_style eq 'pipe' ) {
            $connection_style = 'websocket';
        };
    };
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        connection_style => $connection_style,
        %args,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    SKIP: {
        if( $mech->connection_style($mech) ne 'pipe' ) {
            note "Fetching tabs via HTTP";

            my @tabs;
            my $lives = eval {
                my $list = $mech->transport->list_tabs;
                @tabs = $list->get;
                1
            };
            ok $lives, "We survive listing the tabs from the transport"
                or diag $@;
            cmp_ok 0+@tabs, '>', 0, "We have at least one tab";

        } else {
            skip "Pipe transport doesn't have the JSON http endpoint", 2;
        };
    };

    my @tabs;
    my $lives = eval {
        @tabs = $mech->list_tabs->get;
        1
    };
    ok $lives, "We survive listing the tabs from Mechanize"
        or diag $@;
    cmp_ok 0+@tabs, '>', 0, "We have at least one tab";
});
