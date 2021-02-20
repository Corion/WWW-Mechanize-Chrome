#!perl
use strict;
use warnings;
use File::Basename;

# This is a simple performance hack to move testing of these three files
# to a separate step for easier parallelization as each file takes about
# three or four seconds to run.

my $dir = dirname($0);

our @files = qw<
        65-is_visible_none.html
        65-is_visible_remove.html
        65-is_visible_reload.html
>;

push @INC, '.';
do "$dir/65-is_visible.t";
