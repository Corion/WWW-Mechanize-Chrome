#!perl -w
use strict;
use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;

my $mech = WWW::Mechanize::Chrome->new();
$mech->get_local('links.html');

$mech->eval_in_page(<<'JS');
    alert('Hello Frankfurt.pm');
JS

<>;

=head1 NAME

javascript.pl - execute Javascript in a page

=head1 SYNOPSIS

  perl javascript.pl

=head1 DESCRIPTION

B<This program> demonstrates how to execute simple
Javascript in a page.

=cut
