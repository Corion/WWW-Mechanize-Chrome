#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use lib '.';
use File::Temp qw(tempfile);

use t::helper;
use Log::Log4perl qw(:easy);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my @tests= (
    # PDF only works with headless Chrome
    { format => 'pdf', like => qr/^%PDF-/ },
    { format => 'png', like => qr/^.PNG/, },
    #{ format => 'jpg', like => qr/^......JFIF/, },
);

my $testcount = (1+@tests*2+2);

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount * @instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my @delete;
END {
    for( @delete ) {
        unlink $_
            or diag "Couldn't remove tempfile '$_': $!";
    }
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    t::helper::safe_get_local($mech, '50-click.html');
    for my $test ( @tests ) {
        my $format= $test->{format};
        my $content= eval { t::helper::safe_render_content($mech, format => $format ); };
        SKIP: {
            if( $@ ) {
                skip "$@", 2;
            };

            my $shortcontent = substr( $content, 0, 30 );
            like $shortcontent, $test->{like}, "->render_content( format => '$format' )"
                or diag $shortcontent;
            my @delete;
            my( $tempfh,$outfile )= tempfile;
            close $tempfh;
            push @delete, $outfile;
            eval { t::helper::safe_render_content($mech, format => $format, filename => $outfile ); };
            my($res, $reason)= (undef, "Outfile '$outfile' was not created");
            if( $@ ) {
                $reason = $@;
            } elsif(-f $outfile) {
                if( open my $fh, '<:raw', $outfile ) {
                    local $/;
                    my $content= <$fh>;
                    $res= $content =~ $test->{like}
                        or $reason= "Content did not match /$test->{like}/: " . substr($content,0,10);
                } else {
                    $reason= "Couldn't open '$outfile': $!";
                };
            };
            ok $res, "->render_content to file"
                or diag $reason;
        };
    };

    my $content= eval { t::helper::safe_content_as_pdf($mech, format => 'A4' ); };
    SKIP: {
        if( $@ ) {
            skip "$@", 1;
        };

        my $shortcontent = substr( $content, 0, 30 );
        like $shortcontent, qr/^%PDF-/, "looks like PDF"
            or diag $shortcontent;
        my @delete;
        my( $tempfh,$outfile )= tempfile;
        close $tempfh;
        push @delete, $outfile;
        eval { t::helper::safe_content_as_pdf($mech, format => 'A4', filename => $outfile ); };
        my($res, $reason)= (undef, "Outfile '$outfile' was not created");
        if( $@ ) {
            $reason = $@;
        } elsif(-f $outfile) {
            if( open my $fh, '<:raw', $outfile ) {
                local $/;
                my $content= <$fh>;
                $res= $content =~ qr/^%PDF-/,
                    or $reason= "Content did not match /^%PDF-/: " . substr($content,0,10);
            } else {
                $reason= "Couldn't open '$outfile': $!";
            };
        };
        ok $res, "->content_as_pdf to file"
            or diag $reason;
    };
});

alarm(0);
