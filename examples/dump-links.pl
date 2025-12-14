#!/usr/bin/perl
use strict;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;

my $mech = WWW::Mechanize::Chrome->new();

$mech->get_local('links.html');

sleep 5;

print $_->get_attribute('href'), "\n\t-> ", $_->get_attribute('innerHTML'), "\n"
  for $mech->selector('a.download');

=head1 NAME

dump-links.pl - Dump links on a webpage

=head1 SYNOPSIS

From the examples directory:

  perl dump-links.pl

=head1 DESCRIPTION

This program demonstrates how to read elements out of the Chrome DOM
and how to get at text within nodes.  It prints links with the CSS
class "download" from a file provided with the distribution.


=cut
