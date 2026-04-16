#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

{
    package My::HTML;
    use overload '""' => sub {
        return ${$_[0]}
    };
}

package main;

sub equivalent_html_ok {
    my( $c, $content, $name ) = @_;
    for ($c,$content) {
        s/\s+/ /msg; # normalize whitespace
        s/> </></g;
        s/\s*$//;
    };

    is $c, $content, $name;
};

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

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

    t::helper::safe_update_html($mech, $content);
    my $c = t::helper::safe_content($mech);
    equivalent_html_ok( $c, $content, "Setting the browser content works");

    my $html = '<html><head></head><body><b>Hi</b></body></html>';
    my $html_ref = bless \$html => 'My::HTML';
    t::helper::safe_update_html($mech, "$html_ref" ); # works
    equivalent_html_ok( t::helper::safe_content($mech), $html, "Setting the content works from a stringified object");

    t::helper::safe_update_html($mech,  $html_ref  ); # halted
    equivalent_html_ok( t::helper::safe_content($mech), $html, "Setting the content works from an object with stringification");
});
