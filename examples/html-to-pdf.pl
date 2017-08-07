#!perl -w
use strict;
use WWW::Mechanize::Chrome;

my $mech = WWW::Mechanize::Chrome->new(
    headless => 1, # otherwise, PDF printing will not work
);

for my $url (@ARGV) {
    print "Loading $url";
    $mech->get($url);

    my $fn= 'screen.pdf';
    my $page_pdf = $mech->content_as_pdf(
        filename => $fn,
    );
    print "\nSaved $url as $fn\n";
};