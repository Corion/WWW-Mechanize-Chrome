#!perl -w
use strict;
use Test::More;
use File::Basename;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $testcount = 7;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

my %args;
sub new_mech {
    # Just keep these to pass the parameters to new instances
    if( ! keys %args ) {
        %args = @_;
    };
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        %args,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_; # so we move references

    if( $ENV{WWW_MECHANIZE_CHROME_TRANSPORT}
        and $ENV{WWW_MECHANIZE_CHROME_TRANSPORT} eq 'Chrome::DevToolsProtocol::Transport::Mojo'
    ) {
        SKIP: {
            skip "Chrome::DevToolsProtocol::Transport::Mojo doesn't support port reuse", $testcount
        };
        return;
    };

    my $app = $mech->driver;
    my $transport = $app->transport;
    $mech->{autoclose} = 1;
    my $pid = delete $mech->{pid}; # so that the process survives

    # Add one more, just to be on the safe side, so that Chrome doesn't close
    # immediately again:
    my $info = $mech->driver->createTarget()->get;
    my $targetId = $mech->driver->targetId; # this one should close once we discard it

    my @tabs = $app->getTargets()->get;
    note "Tabs open in PID $pid: ", 0+@tabs;

    note "Releasing mechanize $pid";
    undef $mech; # our own tab should now close automatically
    note "Released mechanize";

    sleep 1;

    SKIP: {
        # In some Chrome versions, Chrome goes away when we closed our websocket?!
        note "Listing tabs";
        my @new_tabs;
        my $ok = eval { @new_tabs = $app->getTargets()->get; 1 };
        if( ! $ok ) {
            skip "$@", $testcount;
        };

        if (! is scalar @new_tabs, @tabs-1, "Our tab was presumably closed") {
            for (@new_tabs) {
                diag $_->{title};
            };
        };
        if( my @kept = grep { $_->{targetId} eq $targetId } @new_tabs ) {
            pass "And it was our tab that was closed";
            use Data::Dumper;
            diag Dumper \@kept;
        } else {
            pass "And it was our tab that was closed";
        };

    my $magic = sprintf "%s - %s", basename($0), $$;
    #diag "Tab title is $magic";
    # Now check that we don't open a new tab if we try to find an existing tab:
    $mech = WWW::Mechanize::Chrome->new(
        autodie   => 0,
        autoclose => 0,
        reuse     => 1,
        new_tab   => 1,
        driver    => $app,
        driver_transport => $transport,
        %args,
    );
    $mech->update_html(<<HTML);
    <html><head><title>$magic</title></head><body>Test</body></html>
HTML
    my $c = $mech->content;
    like $c, qr/\Q$magic/, "We can read our content back immediately";

    undef $mech;
    sleep 1; # to give chrome time to reopen its socket for our tab

    # Now check that we don't open a new tab if we try to find an existing tab:
    $mech = WWW::Mechanize::Chrome->new(
        autodie   => 0,
        autoclose => 0,
        tab       => qr/^\Q$magic/,
        reuse     => 1,
        driver    => $app,
        driver_transport => $transport,
        %args,
    );
    $c = $mech->content;
    like $c, qr/\Q$magic/, "We selected the existing tab"
        or do { diag $_->{title} for $mech->driver->getTargets()->get };

    # Now activate the tab and connect to the "current" tab
    # This is ugly for a user currently using that Chrome instance,
    # but hey, they should be watching in amazement instead of surfing
    # while we test
    #$app->activate_tab($mech->tab)->get;
    undef $mech,
    sleep 2; # to make the socket available again

    $mech = WWW::Mechanize::Chrome->new(
        autodie   => 0,
        autoclose => 0,
        tab       => 'current',
        driver    => $app,
        driver_transport => $transport,
        %args,
    );
    $c = $mech->content;
    like $mech->content, qr/\Q$magic/, "We connected to the current tab"
        or do { diag $_->{title} for $mech->driver->getTargets()->get() };
    $mech->autoclose_tab(1);

    undef $mech; # and close that tab

    # Now try to connect to "our" now closed tab
    my $lived = eval {
        $mech = WWW::Mechanize::Chrome->new(
            autodie          => 1,
            tab              => qr/\Q$magic/,
            reuse            => 1,
            driver           => $app,
            driver_transport => $transport,
            %args,
        );
        1;
    };
    my $err = $@;
    is $lived, undef, 'We died trying to connect to a non-existing tab';
    if( $] < 5.014 ) {
        SKIP: {
            skip "Perl pre 5.14 destructor eval clears \$\@ sometimes", 1;
        };
    } else {
        like $err, qr/Couldn't find a tab matching/, 'We got the correct error message';
    };

    if( $pid ) {
        WWW::Mechanize::Chrome->kill_child('SIGKILL', $pid, undef);
    };
    %args = ();
    };
});
