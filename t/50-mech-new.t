#!perl -w
use strict;
use Test::More tests => 3;
use Data::Dumper;
use Chrome::DevToolsProtocol;

my $c = Chrome::DevToolsProtocol->new();
isa_ok $c, 'Chrome::DevToolsProtocol';

cmp_ok $c->protocol_version, '>=', '0.1', "We have a protocol version";

diag "Open tabs";

my ($h,$d) = $c->request(
    {Tool => 'DevToolsService' }, { command => 'list_tabs' },
);
my @tabs = @{ $d->{data} };

my $target_tab = $tabs[ 0 ];
diag "Attaching to tab $target_tab->[1]";

#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => $target_tab->[0], }, { command => 'attach' },
#);

my $tab = $c->attach( $target_tab->[0] );
my $res = $tab->eval('1+1');
is $res, 2, "Simple expressions work in tab";

isa_ok $tab, 'Chrome::DevToolsProtocol::Tab';

#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => 4, }, { command => 'evaluate_javascript', data => '1+1', },
#);
#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => 4, }, { command => 'evaluate_javascript', data => 'alert("Hello")', },
#);

diag "Evaluating JS code";

my $ext_id = 'jmpeoiheiamlhddpmfekgdicpmajdjoj';
                         #
my $eval = $c->extension($ext_id);
my $res = $eval->eval('1+1');
is $res, 2, "Simple expressions work";

#$res = $eval->eval('chrome.tabs');
#is ref $res, 'HASH', "We can access the 'tabs' object";

# XXX How can we return asynchronous results?
# XXX We need to send an event through the repl extension
$res = $eval->eval(<<JS);
    chrome.tabs.create({}, function(tab){
        console.log("Created new tab "+tab.id);
        var p=chrome.extension.connect("$ext_id",{});
        p.postMessage({'new_tab':tab.id});
        //chrome.extension.sendRequest("$ext_id",{'new_tab': tab.id}, function(any response) {});
        console.log("Created new tab (2)");
    })
JS

is $res, 2, "Simple expressions work";


# Read some more events
AnyEvent->condvar->recv;