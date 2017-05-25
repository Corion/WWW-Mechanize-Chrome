#!perl -T
use strict;
use warnings;

use Test::More tests => 1;
use Log::Log4perl qw(:easy);

my $module;

BEGIN {
   $module  = "WWW::Mechanize::Chrome";
   require_ok( $module );
}

diag( sprintf "Testing %s %s, Perl %s", $module, $module->VERSION, $] );

for (sort grep /\.pm\z/, keys %INC) {
   s/\.pm\z//;
   s!/!::!g;
   eval { diag(join(' ', $_, $_->VERSION || '<unknown>')) };
}
