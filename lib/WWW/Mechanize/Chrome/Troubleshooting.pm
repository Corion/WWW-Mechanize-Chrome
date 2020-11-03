=pod

=head1 NAME

WWW::Mechanize::Chrome::Troubleshooting - Things to watch out for

=head1 INSTALLATION

=head2 Chrome is installed but Perl does not connect to it

If you notice that tests get skipped and/or the module installs
but "does not seem to work", most likely you need to close ALL your Chrome
windows. If you want Perl to share your browser, you will need to start Chrome
yourself with the C<<--remote-debugging-port=9222>> command line switch.

=head2 Tests fail with URLs that do not appear in the distribution files

If you notice that tests ( most likely, C<t/51-mech-links.t> ) fail with
URLs that are not on C<localhost> or C<127.0.0.1>, another not entirely unlikely
explanation is that your machine or your browser has been infected by some
"Search Plugin" redirector which exfiltrates your browsing history or redirects
your search engine or banking websites to other websites.

For confirmation and/or finding out how to remove the offender, maybe a
search from a different machine for the URLs injected additionally into the
test pages helps you identify the offender.

=head1 OPERATION

=head2 Chrome / Chromium best practices

Install your own version of Chrome/Chromium locally and disable automatic
updates. This prevents the API from changing under your scripts.

=head2 File downloads don't work

Chrome / Chromium doesn't have an API for determining whether a download
completed or not. Chrome versions v62 and v63 do have working downloads, but
Chrome v64 does not send the appropriate API messages.

=head2 Timeout when launching script while Chrome is running

You get the error message

  Timeout while connecting to localhost:9222. Do you maybe have a non-debug
  instance of Chrome already running?

Most likely you already launched the Chrome binary without supplying the
C<--remote-debugging-port> option. Either stop all Chrome instances and
(re)launch them using the C<--remote-debugging-port> on the command line or
launch a separate Chrome session using a separate data directory using
the C<data_directory> option.

=head2 Lost UI shared context

When Chrome is run in headless mode, Chrome throws a C<Lost UI shared context>
error. This error can be ignored and does not affect the operation of this
module.

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

Copyright 2010-2020 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

package WWW::Mechanize::Chrome::Troubleshooting;
our $VERSION = '0.61';
1;
