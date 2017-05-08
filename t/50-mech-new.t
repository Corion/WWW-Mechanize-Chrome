#!perl -w
use strict;
use Test::More;
use File::Basename;

use WWW::Mechanize::Chrome;

use lib 'inc', '../inc', '.';
use Test::HTTP::LocalServer;

use t::helper;

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 2*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 12, sub {
    my( $file, $mech ) = splice @_; # so we move references

    my $app = $mech->driver;
    $mech->{autoclose} = 1;

    my @tabs = $app->list_tabs()->get;
    diag 0+@tabs;

    sleep 1;

    undef $mech; # our own tab should now close automatically
    
    sleep 1;

    my @new_tabs = $app->list_tabs()->get;

    if (! is scalar @new_tabs, @tabs-1, "Our tab was presumably closed") {
        for (@new_tabs) {
            diag $_->{title};
        };
    };

    my $magic = sprintf "%s - %s", basename($0), $$;
    #diag "Tab title is $magic";
    # Now check that we don't open a new tab if we try to find an existing tab:
    $mech = WWW::Mechanize::Chrome->new(
        autodie => 0,
        autoclose => 0,
        reuse => 1,
    );
    $mech->update_html(<<HTML);
    <html><head><title>$magic</title></head><body>Test</body></html>
HTML

    undef $mech;

    # Now check that we don't open a new tab if we try to find an existing tab:
    $mech = WWW::Mechanize::Chrome->new(
        autodie => 0,
        autoclose => 0,
        tab => qr/^\Q$magic/,
        reuse => 1,
    );
    my $c = $mech->content;
    like $mech->content, qr/\Q$magic/, "We selected the existing tab"
        or do { diag $_->{title} for $mech->driver->list_tabs() };

    # Now activate the tab and connect to the "current" tab
    # This is ugly for a user currently using Firefox, but hey, they
    # should be watching in amazement instead of surfing while we test
    $app->activate_tab($mech->tab)->get;
    $mech = WWW::Mechanize::Chrome->new(
        autodie => 0,
        autoclose => 0,
        tab => 'current',
    );
    $c = $mech->content;
    like $mech->content, qr/\Q$magic/, "We connected to the current tab"
        or do { diag $_->{title} for $mech->application->openTabs() };
    $mech->autoclose_tab($mech->tab);

    undef $mech; # and close that tab

    # Now try to connect to "our" now closed tab
    my $lived = eval {
        $mech = WWW::Mechanize::Firefox->new(
            autodie => 1,
            tab => qr/\Q$magic/,
        );
        1;
    };
    my $err = $@;
    is $lived, undef, 'We died trying to connect to a non-existing tab';
    # Something within the eval {} block above kills $@. Likely, some destructor
    # somewhere, maybe in MozRepl::RemoteObject.
    like $err, q{/Couldn't find a tab matching/}, 'We got the correct error message';

});