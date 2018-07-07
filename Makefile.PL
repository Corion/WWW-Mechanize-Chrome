# -*- mode: perl; c-basic-offset: 4; indent-tabs-mode: nil; -*-

use strict;
use ExtUtils::MakeMaker qw(WriteMakefile);
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# Normalize version strings like 6.30_02 to 6.3002,
# so that we can do numerical comparisons on it.
my $eumm_version = $ExtUtils::MakeMaker::VERSION;
$eumm_version =~ s/_//;

my $module = 'WWW::Mechanize::Chrome';
(my $main_file = "lib/$module.pm" ) =~ s!::!/!g;
(my $distbase = $module) =~ s!::!-!g;

my @tests = map { glob $_ } 't/*.t', 't/*/*.t';

my %module = (
    NAME                => $module,
    AUTHOR              => q{Max Maischein <corion@cpan.org>},
    VERSION_FROM        => $main_file,
    ABSTRACT_FROM       => $main_file,
    META_MERGE => {
        "meta-spec" => { version => 2 },
        resources => {
            repository => {
                web => "https://github.com/Corion/$distbase",
                url => "git://github.com/Corion/$distbase.git",
                type => 'git',
            }
        },
        dynamic_config   => 0, # we promise to keep META.* up-to-date
        x_static_install => 1, # we are pure Perl and don't do anything fancy
    },

    MIN_PERL_VERSION => '5.010', # I use // in some places

    'LICENSE'=> 'perl',

    PL_FILES            => {},
    BUILD_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },

    PREREQ_PM => {
        'Exporter'           => 5, # for 'import'
        'POSIX'              => 0, # for 'setsid' on POSIXish systems
        'File::Spec'         => 0,

        'Filter::signatures' => '0.09',
        'Carp'               => 0,
        'Future'             => 0,
        'Try::Tiny'          => 0,
        # This actually is optional
        # You need one of the following event loops:
        # AnyEvent, IO::Async, Mojolicious
        'AnyEvent'           => 0,
        'AnyEvent::Future'   => 0,
        'AnyEvent::WebSocket::Client' => 0,

        # This is a developer-only prerequisite, but oh well
        'Algorithm::Loops'   => 0,

        'Log::Log4perl'      => 0, # configurable logging

        'URI'                => 0,    # For URL handling
        'URI::file'          => 0,    # For URL handling, just to be explicit
        'Future::HTTP'       => 0.06, # fixes Mojolicious error handling
        'JSON'               => 0,
        'Moo'                => 2, # for some hashes-as-objects

        'HTTP::Response'                   => 0,
        'HTTP::Headers'                    => 0,
        'Scalar::Util'                     => 0, # we need 'weaken' and 'blessed'
		'MIME::Base64'                     => 0,
        'File::Basename'                   => 0,
        'WWW::Mechanize::Link'             => 0,
        'HTML::Selector::XPath'            => 0,
        'IO::Socket::INET'                 => 0,
        'Storable'                         => 0, # for dclone
        'Object::Import'                   => 0,

        # for extracting element screenshots, loaded dynamically
        'Imager'                           => 0,
        'Imager::File::PNG'                => 0,
    },
    TEST_REQUIRES => {
        'Test::More'   => 0,
        'Test::Deep'   => 0,
        'Data::Dumper' => 0,
        'Image::Info'  => 0,
        'Test::HTTP::LocalServer' => 0.61, # we want the improved IPC
        'URI'          => 0,
        'URI::file'    => 0,
    },

    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => "$distbase-*" },

    test            => { TESTS => join( ' ', @tests ) },
);

# This is so that we can do
#     require 'Makefile.PL'
# and then call get_module_info

sub get_module_info { %module }

if( ! caller ) {
    # I should maybe use something like Shipwright...
    regen_README($main_file);
    regen_EXAMPLES();
    WriteMakefile1(get_module_info);
};

1;

sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
        delete $params{BUILD_REQUIRES};
    }
    if ($params{TEST_REQUIRES} and $eumm_version < 6.64) {
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{TEST_REQUIRES}} };
        delete $params{TEST_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
    delete $params{META_MERGE} if $eumm_version < 6.46;
    delete $params{META_ADD} if $eumm_version < 6.46;
    delete $params{LICENSE} if $eumm_version < 6.31;
    delete $params{AUTHOR} if $] < 5.005;
    delete $params{ABSTRACT_FROM} if $] < 5.005;
    delete $params{BINARY_LOCATION} if $] < 5.005;

    WriteMakefile(%params);
}

sub regen_README {
    # README is the short version that just tells people what this is
    # and how to install it
    eval {
        # Get description
        my $readme = join "\n",
            pod_section($_[0], 'NAME', 'no heading' ),
            pod_section($_[0], 'DESCRIPTION' ),
            <<INSTALL,

INSTALLATION

This is a Perl module distribution. It should be installed with whichever
tool you use to manage your installation of Perl, e.g. any of

  cpanm .
  cpan  .
  cpanp -i .

Consult http://www.cpan.org/modules/INSTALL.html for further instruction.
Should you wish to install this module manually, the procedure is

  perl Makefile.PL
  make
  make test
  make install

INSTALL
            pod_section($_[0], 'REPOSITORY'),
            pod_section($_[0], 'SUPPORT'),
            pod_section($_[0], 'TALKS'),
            pod_section($_[0], 'KNOWN ISSUES'),
            pod_section($_[0], 'BUG TRACKER'),
            pod_section($_[0], 'CONTRIBUTING'),
            pod_section($_[0], 'SEE ALSO'),
            pod_section($_[0], 'AUTHOR'),
            pod_section($_[0], 'LICENSE' ),
            pod_section($_[0], 'COPYRIGHT' ),
    ;
        update_file( 'README', $readme );
    };
    # README.mkdn is the documentation that will be shown as the main
    # page of the repository on Github. Hence we recreate the POD here
    # as Markdown
    eval {
        require Pod::Markdown;

        my $parser = Pod::Markdown->new();

        # Read POD from Module.pm and write to README
        $parser->parse_from_file($_[0]);
        my $readme_mkdn = <<STATUS . $parser->as_markdown;

[![Travis Build Status](https://travis-ci.org/Corion/$distbase.svg?branch=master)](https://travis-ci.org/Corion/$distbase)
[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/github/Corion/$distbase?branch=master&svg=true)](https://ci.appveyor.com/project/Corion/$distbase)

CONTRIBUTING

See lib/WWW/Mechanize/Chrome/Contributing.pod

STATUS
        update_file( 'README.mkdn', $readme_mkdn );
    };
}

sub pod_section {
    my( $filename, $section, $remove_heading ) = @_;
    open my $fh, '<', $filename
        or die "Couldn't read '$filename': $!";

    my @section =
        grep { /^=head1\s+$section/.../^=/ } <$fh>;
    pop @section if $section[-1] =~ /^=/;
    shift @section if $remove_heading;

    # Trim the section
    if( @section ) {
        pop @section
            while $section[-1] =~ /^\s*$/;
        shift @section
            while $section[0] =~ /^\s*$/;
    };

    @section = map { $_ =~ s!^=\w+\s+!!; $_ } @section;
    return join "", @section;
}

sub regen_EXAMPLES {
    my $perl = $^X;
    if ($perl =~/\s/) {
        $perl = qq{"$perl"};
    };
    my $examples = `$perl -w examples/gen_examples_pod.pl`;
    if ($examples) {
        warn "(Re)Creating lib/WWW/Mechanize/Chrome/Examples.pm\n";
        $examples =~ s/\r\n/\n/g;
        update_file( 'lib/WWW/Mechanize/Chrome/Examples.pm', $examples );
    };
};

sub update_file {
    my( $filename, $new_content ) = @_;
    my $content;
    if( -f $filename ) {
        open my $fh, '<', $filename
            or die "Couldn't read '$filename': $!";
        binmode $fh;
        local $/;
        $content = <$fh>;
    };

    if( $content ne $new_content ) {
        if( open my $fh, '>', $filename ) {
            binmode $fh;
            print $fh $new_content;
        } else {
            warn "Couldn't (re)write '$filename': $!";
        };
    };
}
