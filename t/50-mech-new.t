#!perl -w
use strict;
use Test::More tests => 3;
use Data::Dumper;
use Chrome::DevToolsProtocol;

my $c = Chrome::DevToolsProtocol->new();
isa_ok $c, 'Chrome::DevToolsProtocol';

cmp_ok $c->protocol_version, '>=', '0.1', "We have a protocol version";

diag "Open tabs";
#warn Dumper $c->request(
#    {Tool => 'DevToolsService' }, { command => 'list_tabs' },
#);

my ($h,$d) = $c->request(
    {Tool => 'DevToolsService' }, { command => 'list_tabs' },
);
my @tabs = @{ $d->{data} };

my $target_tab = $tabs[ -1 ];
diag "Attaching to tab $target_tab->[1]";

#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => $target_tab->[0], }, { command => 'attach' },
#);

my $tab = $c->attach( $tabs[-1]->[0] => sub {
    warn "Tab event\n";
    warn Dumper \@_;
});

isa_ok $tab, 'Chrome::DevToolsProtocol::Tab';

#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => 4, }, { command => 'evaluate_javascript', data => '1+1', },
#);
#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => 4, }, { command => 'evaluate_javascript', data => 'alert("Hello")', },
#);

diag "Evaluating JS code";
warn Dumper $tab->request({
    data => {
           'command' => 'evaluate',
           'arguments' => ['function(){alert("Hello")}.apply(null)'],
    },
});

#sleep 1;
#warn Dumper $c->read_response;

#warn Dumper $c->request( $seq++,
#    {Tool => 'V8Debugger', Destination => 4, }, { command => 'detach' },
#);

#my $e = $c->extension('xxx');
#$e->eval();