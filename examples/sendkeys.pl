#!perl -w
use strict;
use WWW::Mechanize::Chrome::DSL;

get 'https://google.com';

sendkeys string => "test\r";

sleep 10;

=head1 NAME

sendkeys.pl - send keystrokes to a page

=head1 SYNOPSIS

    sendkeys.pl

=head1 DESCRIPTION

B<This program> demonstrates how to type some input into a text field
and then press the C<enter> key.

=cut