#!/usr/bin/perl
use 5.020;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;
Log::Log4perl->easy_init($ERROR);

# First launch Chrome / Chromium with

# chromium --remote-debugging-port=9222 --remote-allow-origins=*

my $mech = WWW::Mechanize::Chrome->new(
    port => 9222,
    headless => 0,
);

$mech->sendkeys( string => "test\n" );

$mech->sleep( 10 );

=head1 DESCRIPTION

This script shows how to attach to a running instance of Chrome. You need
to have launched Chrome with the following command line for this to work:

  chromium --remote-debugging-port=9222 --remote-allow-origins=*

Most likely you can cut down the overly broad C<--remote-allow-origins=*>
to something like C<--remote-allow-origins=http://127.0.0.1:9222>
after you've got it working.

=cut
