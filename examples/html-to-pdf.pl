#!perl -w
use strict;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;

my $url = shift @ARGV
    or  die "Usage: perl $0 <url>\n";

my $mech = WWW::Mechanize::Chrome->new(
    headless => 1, # otherwise, PDF printing will not work
);

print "Loading $url";
$mech->get($url);

my $fn= 'screen.pdf';
my $page_pdf = $mech->content_as_pdf(
    filename => $fn,
);
print "\nSaved $url as $fn\n";

=head1 NAME

html-to-pdf.pl

=head1 SYNOPSIS

   perl html-to-pdf.pl https://www.perl.org/

=head1 DESCRIPTION

This example takes an URL from the command line, renders it and and
saves it as a PDF file in the current directory.
