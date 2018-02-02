=pod

=head1 NAME

WWW::Mechanize::Chrome::Cookbook - Getting things done with WWW::Mechanize::Chrome

=head1 Web Application Testing with Chrome

=head2 Rationale

If you have an application with complex Javascript, you may want to do end to
end tests using WWW::Mechanize::Chrome. You can run your server application and
your test program in the same process if your server application can be run
under PSGI, as most web frameworks do.

Having all data within one process makes it very easy to fudge configuration
values or database entries at just the right time.

=head2 Initializing the web server in your test script

You will need to use a PSGI web server written in Perl that supports event
loops also supported by WWW::Mechanize::Chrome. L<Twiggy> is one such server.
The setup for Twiggy is as follows:

  use Twiggy::Server;
  use File::Temp 'tempdir';
  
  my $port = 5099;
  my $server = Twiggy::Server->new(
      host => '127.0.0.1',
      port => $port,
  );
  
  # Dancer specific parts
  $ENV{DANCER_APPHANDLER} = 'Dancer::Handler::PSGI';
  my $handler = Dancer::Handler->get_handler();
  Dancer::_load_app('App::mykeep');
  my $app = $handler->psgi_app();
  
  # Rest of Twiggy setup
  $server->register_service($app);
  
  # Fudge the config as appropriate for our test
  Dancer::config()->{mykeep}->{notes_dir} = tempdir(
      CLEANUP => 1,
  );
  
  my $mech = WWW::Mechanize::Chrome->new(
  );
  my $res = $mech->get("http://127.0.0.1:$port");
  ok $res->is_success, "We can request the page";

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

Copyright 2010-2017 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

package WWW::Mechanize::Chrome::Cookbook;
our $VERSION = '0.08';
1;
