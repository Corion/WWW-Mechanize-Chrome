use strict;
use File::Spec;
use File::Basename 'dirname';
use WWW::Mechanize::Chrome;

my $mech = WWW::Mechanize::Chrome->new();

sub show_screen() {
    my $page_png = $mech->content_as_png();

    my $fn= File::Spec->rel2abs(dirname($0)) . "/screen.png";
    open my $fh, '>', $fn
        or die "Couldn't create '$fn': $!";
    binmode $fh, ':raw';
    print $fh $page_png;
    close $fh;
    
    #system(qq(start "Progress" "$fn"));
};

$mech->get('http://act.yapc.eu/gpw2017');

show_screen;
