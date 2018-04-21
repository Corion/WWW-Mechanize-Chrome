#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Chrome::DevToolsProtocol;
use WWW::Mechanize::Chrome; # for launching Chrome
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

my $instance_port = 9222;
my @instances = t::helper::browser_instances();
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 6*@instances;
};

sub new_mech {
    my $chrome = WWW::Mechanize::Chrome->new(
        transport => 'Chrome::DevToolsProtocol::Transport::AnyEvent',
        @_
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 6, sub {
    my( $file, $mech ) = splice @_;
    my $chrome = $mech->driver;

    isa_ok $chrome, 'Chrome::DevToolsProtocol';

    my $version = $chrome->protocol_version->get;
    cmp_ok $version, '>=', '0.1', "We have a protocol version ($version)";

    diag "Open tabs";

    my @tabs = $chrome->list_tabs()->get;
    cmp_ok 0+@tabs, '>', 0,
        "We have at least one open (empty) tab";

    my $target_tab = $tabs[ 0 ];

    $chrome->connect(tab => $target_tab)->get();
    my $tab = $chrome->tab;
    isn::t $tab, undef, "Attached to tab '$target_tab->{title}'";

    #warn Dumper $c->request(
    #    {Tool => 'V8Debugger', Destination => $target_tab->[0], }, { command => 'attach' },
    #);

    # die Dumper $chrome->get_domains->get;

    my $res = $chrome->eval('1+1')->get;
    is $res, 2, "Simple expressions work in tab"
        or diag Dumper $res;

       $res = $chrome->eval('var x = {"foo": "bar"}; x')->get;
    is_deeply $res, {foo => 'bar'}, "Somewhat complex expressions work in tab"
        or diag Dumper $res;
});