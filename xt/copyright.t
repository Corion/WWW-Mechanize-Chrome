#!perl
use warnings;
use strict;
use File::Find;
use Test::More tests => 1;
use POSIX 'strftime';

my $this_year = strftime '%Y', localtime;

my $last_modified_year = 0;

my @dirs = grep { -d $_ } ('scripts', 'examples', 'bin', 'lib');

my @files;
sub collect {
    return if (! m{(\.pm|\.pl|\.pod) \z}xmsi);

    my $modified_year = strftime('%Y', localtime((stat($_))[9]));

    open my $fh, '<', $_
        or die "Couldn't read $_: $!";
    my @copyright = map {
                        /\bcopyright\b.*?\d{4}-(\d{4})\b/i
                        ? [ $_ => $1 ]
                        : ()
                    }
                    <$fh>;
    my $copyright = 0;
    for (@copyright) {
        $copyright = $_->[1] > $copyright ? $_->[1] : $copyright;
    };

    push @files, {
        file => $_,
        copyright_lines => \@copyright,
        copyright => $copyright,
        modified => $modified_year,
    };
};

find({wanted => \&collect, no_chdir => 1},
     @dirs
     );

for my $file (@files) {
    $last_modified_year = $last_modified_year < $file->{modified}
                          ? $file->{modified}
                          : $last_modified_year;
};

note "Distribution was last modified in $last_modified_year";

my @out_of_date = grep { $_->{copyright} and $_->{copyright} != $last_modified_year } @files;

if(! is 0+@out_of_date, 0, "All files have a current copyright year ($last_modified_year)") {
    for my $file (@out_of_date) {
        diag sprintf "%s modified %d, but copyright is %d", $file->{file}, $file->{modified}, $file->{copyright};
        diag $_ for map {@$_} @{ $file->{copyright_lines}};
    };
    diag q{To fix (in a rough way, please review) run};
    diag sprintf q{    perl -i -ple 's!(\bcopyright\b.*?\d{4}-)(\d{4})\b!${1}%s!i' %s}, $this_year, join ' ', map { $_->{file} } @out_of_date;
};

