#!perl -w
use strict;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;
Log::Log4perl->easy_init($ERROR);

my $mech = WWW::Mechanize::Chrome->new();

$mech->get( 'https://google.com' );

$mech->sendkeys( string => "test\r" );

$mech->sleep( 10 );

=head1 NAME

sendkeys.pl - send keystrokes to a page

=head1 SYNOPSIS

    perl sendkeys.pl

=head1 DESCRIPTION

B<This program> demonstrates how to type some input into a text field
and then press the C<enter> key.

=cut
