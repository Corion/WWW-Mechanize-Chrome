=pod

=head1 NAME

WWW::Mechanize::Chrome::Cookbook - Getting things done with WWW::Mechanize::Chrome

=head1 Chrome versions

You can find various current Chrome builds at
L<https://chromium.woolyss.com/> .

The recommended approach to automation is to save a Chrome / Chromium version
and disable automatic updates so you can update at a defined point in time
instead and keep the change to your automation under control.

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

=head1 Debugging Headless Sessions

If you want to watch what a headless browser automation run is doing, you can
do so by sending a screencast from WWW::Mechanize::Chrome to a different browser
that supports websockets by using L<Mojolicious::Plugin::PNGCast> from within
your automation session:

    use Mojolicious::Lite;
    use Mojo::Server::Daemon;
    use WWW::Mechanize::Chrome;
    plugin 'PNGCast';

    my $daemon_url = 'http://localhost:3000';

    my $ws_monitor = Mojo::Server::Daemon->new(app => app());
    $ws_monitor->listen([$daemon_url]);
    $ws_monitor->start;

    my $mech = WWW::Mechanize::Chrome->new( headless => 1 );
    $mech->setScreenFrameCallback( sub {
        app->send_frame( $_[1]->{data} )}
    );

    print "Watch progress at $daemon_url\n";
    sleep 5;

    $mech->get('https://example.com');
    # ... more automation

This will send the progress of your headless session to your browser so you can
see the differences between what you expect and what the browser displays.

=head1 SEE ALSO

L<Detecting Chrome Headless|http://antoinevastel.github.io/bot%20detection/2018/01/17/detect-chrome-headless-v2.html>

L<Making Chrome Headless Undetectable|https://intoli.com/blog/making-chrome-headless-undetectable/>

L<Chrome Headless Detection|https://github.com/paulirish/headless-cat-n-mouse>

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

Copyright 2010-2019 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

package WWW::Mechanize::Chrome::Cookbook;
our $VERSION = '0.38';
1;
