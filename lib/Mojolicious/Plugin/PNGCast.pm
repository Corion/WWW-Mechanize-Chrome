package Mojolicious::Plugin::PNGCast;
use strict;
use 5.014;
use Mojo::Base 'Mojolicious::Plugin';
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

use Future::Mojo;

our $VERSION = '0.22';

=head1 NAME

Mojolicious::Plugin::PNGCast - in-process server to display a screencast

=head1 DESCRIPTION

Use this web application to display the screencast of a (headless) web browser
or other arbitrary PNG data sent to it via websocket.

The synopsis shows how to use this plugin to display
a Chrome screencast using L<WWW::Mechanize::Chrome>.

=head1 SYNOPSIS

    use Mojolicious::Lite;
    use WWW::Mechanize::Chrome;
    plugin 'PNGCast';

    my $daemon_url = 'http://localhost:3000';

    my $ws_monitor = Mojo::Server::Daemon->new(app => app());
    $ws_monitor->listen([$daemon_url]);
    $ws_monitor->start;

    $mech->setScreenFrameCallback( sub {
        app->send_frame( $_[1]->{data} )}
    );

    print "Watch progress at $daemon_url\n";
    sleep 5;

    $mech->get('https://example.com');

=cut

has 'clients'         => sub { {} };
has 'last_frame'      => undef;

=head2 C<< $plugin->notify_clients >>

  $plugin->notify_clients( $PNGframe )

Notify all connected clients that they should display the new frame.

=cut

sub notify_clients( $self, @frames ) {
    my $clients = $self->clients;
    for my $client_id (sort keys %$clients ) {
        my $client = $clients->{ $client_id };
        for my $frame (@frames) {
            eval {
                $client->send({ binary => $frame });
            };
        };
    };
}

sub register( $self, $app, $config ) {

    $app->routes->get('/'  => sub {
        my( $c ) = @_;
        $c->res->headers->content_type('text/html');
        $c->res->headers->connection('close');
        $c->render('index')
    });

    $app->routes->websocket( '/ws' => sub {
        my( $c ) = @_;
        $c->inactivity_timeout(300);

        my $client_id = join ":", $c->tx->original_remote_address || $c->tx->remote_address,
                                  $c->tx->remote_port();

        $self->clients->{ $client_id } = $c;
        $c->tx->on( json => sub {
            my( $c, $data ) = @_;
            #warn Dumper $data ;
            warn "Click received (and ignored)";
            #$mech->click( { selector => '//body', single => 1 }, $data->{x}, $data->{y} );
            #$mech->click( { selector => '//body', single => 1 }, $data->{x}, $data->{y} );

        });
        #warn("Client connected");
        if( $self->last_frame ) {
            # send current frame
            $c->send({ binary => $self->last_frame });
        } else {
            # send a standby frame ??
        };
        $c->tx->on( finish => sub {
            my( $c,$code,$reason ) = @_;
            warn "Client gone ($code,$reason)" ;
            delete $self->clients->{ $client_id };
        });
    });

    # Stop our program
    $app->routes->get( '/stop' => sub {
        my( $c ) = @_;
        $c->res->headers->content_type('text/html');
        $c->res->headers->connection('close');
        $c->render('stop');
        Mojo::IOLoop->stop;
    });

    $app->helper( 'send_frame' => sub ( $c, $framePNG ) {
        # send this frame to all connected clients
        if( scalar keys %{ $self->clients } ) {
            Future::Mojo->new->done_next_tick( 1 )
            ->then( sub {
                $self->notify_clients( $framePNG->{data} );
            })->retain;
        } else {
            $self->last_frame( $framePNG->{data} );
        };
    });

    # Install our templates
    push @{$app->renderer->classes}, __PACKAGE__;
    push @{$app->static->classes},   __PACKAGE__;
}

=head1 EXPORTED HTTP ENDPOINTS

This plugin makes the following endpoints available

=over 4

=item *

C</> - the index page

This is an HTML page that opens a websocket to the webserver and listens for
PNG images coming in over that websocket

=item *

C</ws> - the websocket

This is a websocket

=item *

C</stop> - stop the application

This stops the complete Mojolicious application

=back

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org|mailto:www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 CONTRIBUTING

Please see L<WWW::Mechanize::Chrome::Contributing>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2018 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

1
__DATA__

@@ stop.html.ep

<html><body>Bye</body></html>

@@ index.html.ep

<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8"/><title>Hessian</title>
<script>
function install() {
    var output = document.getElementById('hessianHead');
    var status = document.getElementById('status');
    var exampleSocket = new WebSocket(location.origin.replace(/^http/, 'ws')+"/ws");
    exampleSocket.binaryType = 'arraybuffer';
    exampleSocket.onopen = function(evt) {
        status.innerHTML = "Connected";
    };
    exampleSocket.onerror = function(evt) {
        status.innerHTML = "Error:" + evt;
    };
    exampleSocket.onclose = function(evt) {
        status.innerHTML = "Closed";
    };
    exampleSocket.onmessage = function(evt) {
        if (evt.data instanceof ArrayBuffer) {
            var length = evt.data.byteLength;
            var blob = new Blob([evt.data],{type:'image/png'});
            var url = URL.createObjectURL(blob);
            var image = document.getElementById("hessianHead");
            var img = new Image();
            img.onload = function(){
                var ctx = image.getContext("2d");
                ctx.drawImage(img, 0, 0);
            }
            img.src = url;
        }
    };
    output.onclick = function(evt) {
        console.log(evt);
        exampleSocket.send(JSON.stringify( { action:"click", x: evt.offsetX, y: evt.offsetY }));
    }
    status.innerHTML = "Connecting";
};
</script>
</head>
<body onload="javascript:install()">
<canvas id="hessianHead" width="1280" height="800"></canvas>
<div id="status">Javascript required</div><div><a href="/stop">Stop</a></div>
</body></html>
