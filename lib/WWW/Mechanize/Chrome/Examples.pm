package WWW::Mechanize::Chrome::Examples;

###############################################################################
#
# Examples - WWW::Mechanize::Chrome examples.
#
# A documentation only module showing the examples that are
# included in the WWW::Mechanize::Chrome distribution. This
# file was generated automatically via the gen_examples_pod.pl
# program that is also included in the examples directory.
#
# Copyright 2000-2010, John McNamara, jmcnamara@cpan.org
#
# Documentation after __END__
#

use strict;
our $VERSION = '0.07';

1;

__END__

=pod

=head1 NAME

Examples - WWW::Mechanize::Chrome example programs.

=head1 DESCRIPTION

This is a documentation only module showing the examples that are
included in the L<WWW::Mechanize::Chrome> distribution.

This file was auto-generated via the C<gen_examples_pod.pl>
program that is also included in the examples directory.

=head1 Example programs

The following is a list of the 4 example programs that are included in the WWW::Mechanize::Chrome distribution.

=over

=item * L<Example: url-to-image.pl> Take a screenshot of a website

=item * L<Example: html-to-pdf.pl> Convert HTML to PDF

=item * L<Example: dump-links.pl> Dump links on a webpage

=item * L<Example: javascript.pl> Execute Javascript in the webpage context

=back

=head2 Example: url-to-image.pl

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


Download this example: L<http://cpansearch.perl.org/src/CORION/WWW-Mechanize-Chrome-0.07/examples/url-to-image.pl>

=head2 Example: html-to-pdf.pl

    #!perl -w
    use strict;
    use WWW::Mechanize::Chrome;
    
    my $mech = WWW::Mechanize::Chrome->new(
        headless => 1, # otherwise, PDF printing will not work
    );
    
    for my $url (@ARGV) {
        print "Loading $url";
        $mech->get($url);
    
        my $fn= 'screen.pdf';
        my $page_pdf = $mech->content_as_pdf(
            filename => $fn,
        );
        print "\nSaved $url as $fn\n";
    };

Download this example: L<http://cpansearch.perl.org/src/CORION/WWW-Mechanize-Chrome-0.07/examples/html-to-pdf.pl>

=head2 Example: dump-links.pl

    use strict;
    use WWW::Mechanize::Chrome;
    
    my $mech = WWW::Mechanize::Chrome->new();
    
    $mech->get_local('links.html');
    
    sleep 5;
    
    print $_->get_attribute('href'), "\n\t-> ", $_->get_attribute('innerHTML'), "\n"
      for $mech->selector('a.download');
    
    =head1 NAME
    
    dump-links.pl - Dump links on a webpage
    
    =head1 SYNOPSIS
    
    dump-links.pl
    
    =head1 DESCRIPTION
    
    This program demonstrates how to read elements out of the Chrome
    DOM and how to get at text within nodes.
    
    =cut

Download this example: L<http://cpansearch.perl.org/src/CORION/WWW-Mechanize-Chrome-0.07/examples/dump-links.pl>

=head2 Example: javascript.pl

    #!perl -w
    use strict;
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
    
    javascript.pl
    
    =head1 DESCRIPTION
    
    B<This program> demonstrates how to execute simple
    Javascript in a page.
    
    =cut

Download this example: L<http://cpansearch.perl.org/src/CORION/WWW-Mechanize-Chrome-0.07/examples/javascript.pl>

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

Contributed examples contain the original author's name.

=head1 COPYRIGHT

Copyright 2009-2016 by Max Maischein C<corion@cpan.org>.

All Rights Reserved. This module is free software. It may be used, redistributed and/or modified under the same terms as Perl itself.

=cut
