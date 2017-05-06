#!perl -w
use strict;
use Test::More tests => 3;
use Data::Dumper;
use Chrome::DevToolsProtocol;

my $c = Chrome::DevToolsProtocol->new();
isa_ok $c, 'Chrome::DevToolsProtocol';

$c->connect->get();

my $version = $c->protocol_version;
cmp_ok $version, '>=', '0.1', "We have a protocol version ($version)";

diag "Open tabs";

my @tabs = @{ $c->list_tabs()->get };

my $target_tab = $tabs[ 0 ];
diag "Attaching to tab $target_tab->[1]";

#warn Dumper $c->request(
#    {Tool => 'V8Debugger', Destination => $target_tab->[0], }, { command => 'attach' },
#);

my $tab = $c->attach( $target_tab->[0] );
my $res = $tab->eval('1+1');
is $res, 2, "Simple expressions work in tab"
    or diag Dumper $res;

my $res = $tab->eval('{"foo": "bar"}');
is_deeply $res, {foo => 'bar'}, "Somewhat complex expressions work in tab"
    or diag Dumper $res;

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
# chrome.tabs.executeScript(tab.id, code)
# chrome.tabs.onUpdated.addListener()
# Also see http://github.com/AndersSahlin/MailCheckerPlus/blob/master/src/chrome-api-vsdoc.js
# as a stub for the Chrome API
$res = $eval->eval(<<JS);
    chrome.tabs.create({}, function(tab){
        // console.log("Created new tab "+tab.id);
        // alert("Created new tab "+tab.id);
        var p=chrome.extension.connect("$ext_id",{});
        p.postMessage({'new_tab':tab.id});
        //chrome.extension.sendRequest("$ext_id",{'new_tab': tab.id}, function(any response) {});
        console.log("Created new tab (2)"); // Sends a message to Perl
    })
JS

# console.log() sends a (text) message to Perl, as onMessage event
# 'data' => {
#     'log' => 'Created new tab (2)'
# },

is $res, 2, "Simple expressions work";


# Read some more events
AnyEvent->condvar->recv;

# chrome.experimental.webNavigation.onDOMContentLoaded.addListener(function(object details) {...});
# chrome.experimental.webNavigation.onErrorOccurred.addListener(function(object details) {...});