#!perl -w
package main;
use strict;
use WWW::Mechanize::Edge;
use Log::Log4perl ':easy';
Log::Log4perl->easy_init($TRACE);

my $mech = WWW::Mechanize::Edge->new(
);

$mech->get('https://example.com');

