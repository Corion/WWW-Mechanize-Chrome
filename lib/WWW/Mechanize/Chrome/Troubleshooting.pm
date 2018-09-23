=pod

=head1 NAME

WWW::Mechanize::Chrome::Troubleshooting - Things to watch out for

=head1 INSTALLATION

=head2 Chrome is installed but Perl does not connect to it

If you notice that tests get skipped and/or the module installs
but "does not seem to work", most likely you need to close ALL your Chrome
windows. If you want Perl to share your browser, you will need to start Chrome
yourself with the C<<--remote-debugging-port=9222>> command line switch.

=head1 OPERATION

=head2 Chrome / Chromium best practices

Install your own version of Chrome/Chromium locally and disable automatic
updates. This prevents the API from changing under your scripts.

=head2 File downloads don't work

Chrome / Chromium doesn't have an API for determining whether a download
completed or not. Chrome versions v62 and v63 do have working downloads, but
Chrome v64 does not send the appropriate API messages.

=head1 REPORTING AN ISSUE

Ideally you ask your question on the public support forum, as then other people
can also provide you with good answers. Your question should include a short
script of about 20 lines that reproduces the problem. Remember to remove all
passwords from the script.

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org|mailto:www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2018 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

package WWW::Mechanize::Chrome::Troubleshooting;
our $VERSION = '0.22';
1;
