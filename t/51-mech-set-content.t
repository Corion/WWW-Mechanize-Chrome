#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use lib 'inc', '../inc', '.';
use Test::HTTP::LocalServer;
use Log::Log4perl qw(:easy);

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

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

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 2, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my $content = <<HTML;
<html>
<head>
<title>Hello Chrome!</title>
</head>
<body>
<h1>Hello World!</h1>
<p>Hello <b>WWW::Mechanize::Chrome</b></p>
</body>
</html>
HTML

    $mech->update_html($content);

    my $c = $mech->content;
    for ($c,$content) {
        s/\s+/ /msg; # normalize whitespace
        s/> </></g;
        s/\s*$//;
    };

    is $c, $content, "Setting the content works";
});