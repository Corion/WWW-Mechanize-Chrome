#!perl
use strict;
use warnings;
use Log::Log4perl ':easy';
use WWW::Mechanize::Chrome;
use Test::More;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test::HTTP::LocalServer;
#use Devel::FindRef;

use lib '.';
use t::helper;
use Time::HiRes qw(sleep);
if( $^O !~ /mswin/i ) {
    require Time::HiRes;
    Time::HiRes->import('ualarm');
}

Log::Log4perl->easy_init($ERROR);


my $server = t::helper->safe_server(
    #debug => 1
);
my $url = $server->url;

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $testcount = 7;

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
            warn "Forcing style to websocket";
            $connection_style = 'websocket';
        };
    };

    # t::helper::need_minimum_chrome_version( '72.0.0.0', @_ ); # for pipes
    # But we should know not use pipes?!
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        connection_style => $connection_style,
        %args,
        #headless => 0,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_; # so we move references

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    t::helper::safe_get($mech, $url);

    t::helper::safe_update_html($mech, <<"HTML");
    <html>
    <title>Test page with popup</title>
    <body><a href="javascript:window.open('$url')" id="launch_popup">Pop up</a>
    </html>
HTML

    note "Set up Javascript popup";

    my @opened;
    my $opened_tab_f;

    $mech->on( popup => sub( $mech, $tab_f ) {
        # This is a bit heavyweight, but ...
        warn "Already have a future?!"
            if $opened_tab_f;
        note "New tab was detected ($tab_f)";
        $opened_tab_f = $tab_f;
        $opened_tab_f->on_done(sub($tab) {
            note "New window/tab has popped up ($tab)";
            push @opened, $tab;
        });
    });

    #$mech->target->send_message( 'DOM.performSearch', query => "#launch_popup" )->then(sub($results) {
    #    $mech->target->send_message( 'DOM.getSearchResults',
    #            searchId => $results->{searchId},
    #            fromIndex => 0,
    #            toIndex => 0+$results->{resultCount},
    #    );
    #})->get;
    note "Launching Javascript popup";
    t::helper::safe_click($mech, { selector => "#launch_popup" });
    # $mech->sleep(0); # just in case, to get the event loop a chance to catch up
    my @tabs = $mech->list_tabs->get;

#my $orig = \&WWW::Mechanize::Chrome::DESTROY;
#*WWW::Mechanize::Chrome::DESTROY = sub {
#    note "Destroying $_[0]";
#    goto &$orig;
#};

    # Make sure we can access the newly opened tab
    if(! $opened_tab_f) {
        die "We didn't find an opened tab?!";
    }
    $opened_tab_f->get();
    undef $opened_tab_f;
    if( ! isa_ok $opened[0], 'WWW::Mechanize::Chrome' ) {
        fail "We found a tab opened at the new URL";
    } else {
        note "Have popup at $opened[0]";
        $mech->sleep(1); # to give the tab a chance to load
        is $opened[0]->uri, $url, "We found a tab opened at the new URL";
        $opened[0]->autoclose_tab(1);
    };

    #diag Devel::FindRef::track $opened[0];

    $mech->sleep(0.1);
    note "Clearing out opened tabs";
    @opened = ();
    sleep 0.1;
    note "Mech is still $mech";

    my @tabs_after = $mech->list_tabs->get;
    cmp_ok 0+@tabs_after, '<', 0+@tabs, "We autoclosed the newfound tab";

    #$mech->sleep(1);
    note "Set up target=_blank popup";
    t::helper::safe_update_html($mech, <<"HTML");
    <html>
    <title>Test page with popup</title>
    <body><a href="$url" target=_blank id="launch_popup">Pop up</a>
    </html>
HTML

    note "Launching popup";
    t::helper::safe_click($mech, { selector => "#launch_popup" });
    @tabs = $mech->list_tabs->get;
    $opened_tab_f->get();
    undef $opened_tab_f;
    if( ! isa_ok $opened[0], 'WWW::Mechanize::Chrome' ) {
        fail "We found a tab opened at the new URL";
    } else {
        $mech->sleep(1); # to give the tab a chance to load
        is $opened[0]->uri, $url, "We found a tab opened at the new URL";
    };

    #$mech->sleep(1);

    @opened = ();
    sleep 0.1;
    @tabs_after = $mech->list_tabs->get;
    cmp_ok 0+@tabs_after, '<', 0+@tabs, "We autoclosed the newfound tab";

    $mech->unsubscribe( 'popup' );
    t::helper::safe_click($mech, { selector => "#launch_popup" });
    $mech->sleep(0.1);

    is 0+@opened, 0, "We can disable our on_popup callback";

    note "Cleaning up instance $file";
});

alarm(0);

#if( ! $target_tab->{targetId}) {
#    die "This Chrome doesn't want more than one debugger connection";
#} else {
#    $chrome->connect(tab => $target_tab)->get();
#};

done_testing();
