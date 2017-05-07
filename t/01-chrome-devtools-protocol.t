#!perl -w
use strict;
use Test::More tests => 6;
use Data::Dumper;
use Chrome::DevToolsProtocol;

my $chrome = Chrome::DevToolsProtocol->new(
    log => sub {},
);
isa_ok $chrome, 'Chrome::DevToolsProtocol';

my $version = $chrome->protocol_version;
cmp_ok $version, '>=', '0.1', "We have a protocol version ($version)";

diag "Open tabs";

my @tabs = @{ $chrome->list_tabs()->get };
cmp_ok 0+@tabs, '>', 0,
    "We have at least one open (empty) tab";

my $target_tab = $tabs[ 0 ];

my $tab = $chrome->connect(tab => $target_tab)->get();
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
