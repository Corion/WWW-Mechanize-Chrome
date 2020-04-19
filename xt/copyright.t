#!perl
use warnings;
use strict;
use File::Find;
use Test::More tests => 1;
use POSIX 'strftime';

my $this_year = strftime '%Y', localtime;

my $last_modified_year = 0;

my $is_checkout = -d '.git';

require './Makefile.PL';
# Loaded from Makefile.PL
our %module = get_module_info();

my @files;
#my $blib = File::Spec->catfile(qw(blib lib));
find(\&wanted, grep { -d } ('lib'));

if( my $exe = $module{EXE_FILES}) {
    push @files, @$exe;
};

sub wanted {
  push @files, $File::Find::name if /\.p(l|m|od)$/;
}

sub collect {
    my( $file ) = @_;
    note $file;
    my $modified_ts;
    if( $is_checkout ) {
        # diag `git log -1 --pretty="format:%ct" "$file"`;
        $modified_ts = `git log -1 --pretty="format:%ct" "$file"`;
    } else {
        $modified_ts = (stat($_))[9];
    }

    my $modified_year;
    if( $modified_ts ) {
        $modified_year = strftime('%Y', localtime($modified_ts));
    } else {
        $modified_year = 1970;
    };

    open my $fh, '<', $file
        or die "Couldn't read $file: $!";
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

    return {
        file => $file,
        copyright_lines => \@copyright,
        copyright => $copyright,
        modified => $modified_year,
    };
};

my @results;
for my $file (@files) {
    push @results, collect($file);
};

for my $file (@results) {
    $last_modified_year = $last_modified_year < $file->{modified}
                          ? $file->{modified}
                          : $last_modified_year;
};

note "Distribution was last modified in $last_modified_year";

my @out_of_date = grep { $_->{copyright} and $_->{copyright} < $last_modified_year } @results;

if(! is 0+@out_of_date, 0, "All files have a current copyright year ($last_modified_year)") {
    for my $file (@out_of_date) {
        diag sprintf "%s modified %d, but copyright is %d", $file->{file}, $file->{modified}, $file->{copyright};
        diag $_ for map {@$_} @{ $file->{copyright_lines}};
    };
    diag q{To fix (in a rough way, please review) run};
    diag sprintf q{    perl -i -ple 's!(\bcopyright\b.*?\d{4}-)(\d{4})\b!${1}%s!i' %s},
        $this_year,
        join ' ',
        map { $_->{file} } @out_of_date;
};

