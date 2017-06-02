use strict;
use Test::More;
use File::Spec;
use File::Find;
use File::Temp 'tempfile';

my @files;

my $blib = File::Spec->catfile(qw(blib lib));
find(\&wanted, grep { -d } ($blib, 'bin'));

plan tests => scalar @files;
foreach my $file (@files) {
    synopsis_file_ok($file);
}

sub wanted {
    push @files, $File::Find::name if /\.p(l|m|od)$/
        and $_ !~ /\bDSL\.pm$/; # we skip that one as it initializes immediately
}

sub synopsis_file_ok {
    my( $file ) = @_;
    my $name = "SYNOPSIS in $file compiles";
    open my $fh, '<', $file
        or die "Couldn't read '$file': $!";
    my @synopsis = map  { s!^\s\s!!; $_ } # outdent all code for here-docs
                   grep { /^\s\s/ } # extract all verbatim (=code) stuff
                   grep { /^=head1\s+SYNOPSIS$/.../^=/ } # extract Pod synopsis
                   <$fh>;
    if( @synopsis ) {
        my($tmpfh,$tempname) = tempfile();
        print {$tmpfh} join '', @synopsis;
        close $tmpfh; # flush it
        my $output = `$^X -Ilib -c $tempname 2>&1`;
        if( $output =~ /\ssyntax OK$/ ) {
            pass $name;
        } else {
            fail $name;
            diag $output;
            diag $_ for @synopsis;
        };
        unlink $tempname
            or warn "Couldn't clean up $tempname: $!";
    } else {
        SKIP: {
            skip "$file has no SYNOPSIS section", 1;
        };
    };
    
}