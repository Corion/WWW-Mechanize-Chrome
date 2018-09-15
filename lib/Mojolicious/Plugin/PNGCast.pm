package Mojolicious::Plugin::PNGCast;
use strict;
use 5.014;
use Mojo::Base 'Mojolicious::Plugin';
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

use Future::Mojo;

#has 'clients'         => sub { {} };
has 'remote'          => undef; # this should become a list
has 'last_frame'      => undef; # this should become a list

=head2 C<< $plugin->notify_clients >>

  $plugin->notify_clients( {
      type => 'reload',
  });

Notify all connected clients that they should perform actions.

=cut

sub notify_clients( $self, @actions ) {
    # Blow the cache away
    my $old_cache = $self->app->renderer->cache;
    $self->app->renderer->cache( Mojo::Cache->new(max_keys => $old_cache->max_keys));

    my $clients = $self->clients;
    for my $client_id (sort keys %$clients ) {
        my $client = $clients->{ $client_id };
        for my $action (@actions) {
            # Convert path to what the client will likely have requested (duh)

            # These rules should all come from a config file, I guess
            #app->log->info("Notifying client $client_id of '$action->{name}' change to '$action->{path}'");
            $client->send({json => $action });
        };
    };
}

sub register( $self, $app, $config ) {

    $app->routes->get('/'  => sub {
        my( $c ) = @_;
        $c->res->headers->content_type('text/html');
        $c->res->headers->connection('close');
        #$c->render('echo')
        $c->render('index')
    });

    $app->routes->websocket( '/ws' => sub {
        my( $c ) = @_;
        $c->inactivity_timeout(300);
    
        $self->remote( $c );
        $self->remote->tx->on( json => sub {
            my( $c, $data ) = @_;
            #warn Dumper $data ;
            warn "Click received (and ignored)";
            # XXX We need an async click here:
            #$mech->click( { selector => '//body', single => 1 }, $data->{x}, $data->{y} );
            #$mech->click( { selector => '//body', single => 1 }, $data->{x}, $data->{y} );
    
        });
        #warn("Client connected");
        if( $self->last_frame ) {
            #warn("Sending current frame");
            $self->remote->send({ binary => $self->last_frame });
            $self->last_frame(undef);
        } else {
            #warn("Sending standby frame");
            #$self->remote->send({ binary => $static_frame });
        };
        $self->remote->on( finish => sub { my( $c,$code,$reason ) = @_; warn "Client gone ($code,$reason)" });
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
        # send this frame to the browser
        if( $self->remote ) {
            Future::Mojo->new->done_next_tick( 1 )
            ->then( sub {
                $self->remote->send({ binary => $framePNG->{data} });
            })->retain;
        } else {
            $self->last_frame( $framePNG->{data} );
        };
    });

    # Install our templates
    push @{$app->renderer->classes}, __PACKAGE__;
    push @{$app->static->classes},   __PACKAGE__;
}

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
</img>
<div id="status">Disconnected</div><div><a href="/stop">Stop</a></div>
</body></html>
