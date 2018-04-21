#!perl -w

use warnings;
use strict;
use Test::More;
use Data::Dumper;
use File::Find;

=head1 DESCRIPTION

This test checks whether all tests still pass when the optional test
prerequisites for the test are not present.

This is done by using L<Test::Without::Module> to rerun the test while excluding
the optional prerequisite.

=cut

BEGIN {
    eval {
        require CPAN::META::Prereqs;
        require Parse::CPAN::Meta;
        require Perl::PrereqScanner::Lite;
        require Module::CoreList;
        require Test::Without::Module;
        require Capture::Tiny;
        Capture::Tiny->import('capture');
        require Path::Class;
        Path::Class->import('dir');
    };
    if (my $err = $@) {
        warn "# $err";
        plan skip_all => "Prerequisite needed for testing is missing";
        exit 0;
    };
};

my @tests = glob 't/*.t';
plan tests => 0+@tests;

my $meta = Parse::CPAN::Meta->load_file('META.json');

# Find what META.* declares
my $explicit_test_prereqs = CPAN::Meta::Prereqs->new( $meta->{prereqs} )->merged_requirements->as_string_hash;
my $minimum_perl = $meta->{prereqs}->{runtime}->{requires}->{perl} || 5.006;

sub distributed_packages {
    my @modules;
    for( @_ ) {
        dir($_)->recurse( callback => sub {
            my( $child ) = @_;
            if( !$child->is_dir and $child =~ /\.pm$/) {
                push @modules, ((scalar $child->slurp()) =~ m/^\s*package\s+(?:#.*?\n\s+)*(\w+(?:::\w+)*)\b/msg);
            }
        });
    };
    map { $_ => $_ } @modules;
}

# Find what we distribute:
my %distribution = distributed_packages('blib','t');

my $scanner = Perl::PrereqScanner::Lite->new;
for my $test_file (@tests) {
    my $implicit_test_prereqs = $scanner->scan_file($test_file)->as_string_hash;
    my %missing = %{ $implicit_test_prereqs };
    #warn Dumper \%missing;

    for my $p ( keys %missing ) {
        # remove core modules
        if( Module::CoreList::is_core( $p, undef, $minimum_perl)) {
            delete $missing{ $p };
            #diag "$p is core for $minimum_perl";
        } else {
            #diag "$p is not in core for $minimum_perl";
        };

        # remove explicit (test) prerequisites
        for my $k (keys %$explicit_test_prereqs) {
            delete $missing{ $k };
        };
        #warn Dumper $explicit_test_prereqs->as_string_hash;

        # Remove stuff from our distribution
        for my $k (keys %distribution) {
            delete $missing{ $k };
        };
    }

    # If we have no apparent missing prerequisites, we're good
    my @missing = sort keys %missing;

    # Rerun the test without these modules and see whether it crashes
    my @failed;
    for my $candidate (@missing) {
        diag "Checking that $candidate is not essential";
        my @cmd = ($^X, "-MTest::Without::Module=$candidate", "-Mblib", '-w', $test_file);
        my $cmd = join " ", @cmd;

        my ($stdout, $stderr, $exit) = capture {
            system( @cmd );
        };
        if( $exit != 0 ) {
            push @failed, [ $candidate, [@cmd]];
        } elsif( $? != 0 ) {
            push @failed, [ $candidate, [@cmd]];
        };
    };
    is 0+@failed, 0, $test_file
        or diag Dumper \@failed;

};

done_testing;