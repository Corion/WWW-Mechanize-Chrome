#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Test::HTTP::LocalServer;
use Data::Dumper;
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
#Log::Log4perl->easy_init($TRACE)
#    if $^O =~ /darwin/i;

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 11;
if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    my ($site,$estatus) = ($server->url,200);

    my $res = $mech->get($site);

    for( 1..10 ) {
        my @input = $mech->xpath('//input[@name="q"]');
    };
    is scalar @{ $mech->driver->listener->{'DOM.setChildNodes'} || []}, 0, "We don't accumulate listeners";

    my $destroyed = 0;
    my $old_destroy = \&Chrome::DevToolsProtocol::EventListener::DESTROY;
    no warnings 'redefine';
    local *Chrome::DevToolsProtocol::EventListener::DESTROY = sub {
        $destroyed++;
        goto &$old_destroy;
    };
    # Set up our listener
    $mech->on_dialog(sub {
        # ...
    });
    is scalar @{ $mech->driver->listener->{'Page.javascriptDialogOpening'} }, 1, "We have exactly one listener";

    # Remove our listener
    $mech->on_dialog(undef);
    is scalar @{ $mech->driver->listener->{'Page.javascriptDialogOpening'} }, 0, "We remove it";
    is $destroyed, 1, "our destructor gets called";

    is scalar @{ $mech->driver->listener->{'Runtime.consoleAPICalled'} }, 1, "We have one console listener already";
    $destroyed = 0;
    my $called = 0;
    my $console = $mech->add_listener('Runtime.consoleAPICalled', sub {
        $called++;
    });
    is scalar @{ $mech->driver->listener->{'Runtime.consoleAPICalled'} }, 2, "We have one listener more";
    $mech->driver->on_response(undef, '{"method":"Runtime.consoleAPICalled"}');
    is $called, 1, "Our handler was called";
    $console->unregister;
    $called = 0;
    $destroyed = 0;
    $mech->driver->on_response(undef, '{"method":"Runtime.consoleAPICalled"}');
    is $called, 0, "Our handler was not called after manual removal";
    is scalar @{ $mech->driver->listener->{'Runtime.consoleAPICalled'} }, 1, "We remove it";
    undef $console;
    is $destroyed, 1, "our destructor gets called";

    $called = 0;
    $console = $mech->add_listener('Runtime.consoleAPICalled', sub {
        $called++;
    });
    $mech->remove_listener( $console );
    $mech->driver->on_response(undef, '{"method":"Runtime.consoleAPICalled"}');
    is $called, 0, "Our handler was not called after manual removal via ->remove_listener";
    note "Test with one browser instance finished";
});
note "Stopping local HTTP server";
$server->stop;
note "Shutting down";
