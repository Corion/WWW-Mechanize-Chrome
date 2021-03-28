package Chrome::DevToolsProtocol;
use 5.010; # for //
use strict;
use warnings;
use Moo;
use PerlX::Maybe;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Future;
use Future::HTTP;
use Carp qw(croak carp);
use JSON;
use Data::Dumper;
use Chrome::DevToolsProtocol::Transport;
use Scalar::Util 'weaken', 'isweak';
use Try::Tiny;
use URI;

our $VERSION = '0.66';
our @CARP_NOT;

=head1 NAME

Chrome::DevToolsProtocol - asynchronous dispatcher for the DevTools protocol

=head1 SYNOPSIS

    # Usually, WWW::Mechanize::Chrome automatically creates a driver for you
    my $driver = Chrome::DevToolsProtocol->new(
        port => 9222,
        host => '127.0.0.1',
        auto_close => 0,
        error_handler => sub {
            # Reraise the error
            croak $_[1]
        },
    );
    $driver->connect( new_tab => 1 )->get

=head1 METHODS

=head2 C<< ->new( %args ) >>

    my $driver = Chrome::DevToolsProtocol->new(
        port => 9222,
        host => '127.0.0.1',
        auto_close => 0,
        error_handler => sub {
            # Reraise the error
            croak $_[1]
        },
    );

These members can mostly be set through the constructor arguments:

=over 4

=cut

sub _build_log( $self ) {
    require Log::Log4perl;
    Log::Log4perl->get_logger(__PACKAGE__);
}

=item B<host>

The hostname to connect to

=cut

has 'host' => (
    is => 'ro',
    default => '127.0.0.1',
);

=item B<port>

The port to connect to

=cut

has 'port' => (
    is => 'ro',
    default => 9222,
);

=item B<json>

The JSON decoder used

=cut

has 'json' => (
    is => 'ro',
    default => sub { JSON->new },
);

=item B<ua>

The L<Future::HTTP> instance to talk to the Chrome DevTools

=cut

has 'ua' => (
    is => 'ro',
    default => sub { Future::HTTP->new },
);

=item B<tab>

Which tab to reuse (if any)

=cut

has 'tab' => (
    is => 'rw',
);

=item B<log>

A premade L<Log::Log4perl> object to act as logger

=cut

has '_log' => (
    is => 'ro',
    default => \&_build_log,
);

has 'receivers' => (
    is => 'ro',
    default => sub { {} },
);

has 'reader_fh' => (
    is => 'ro',
);

has 'writer_fh' => (
    is => 'ro',
);

=item B<on_message>

A callback invoked for every message

=cut

has 'on_message' => (
    is => 'rw',
    default => undef,
);

has '_one_shot' => (
    is => 'ro',
    default => sub { [] },
);

has 'listener' => (
    is => 'ro',
    default => sub { {} },
);

has 'sequence_number' => (
    is => 'rw',
    default => sub { 1 },
);

=item B<transport>

The event-loop specific transport backend

=cut

has 'transport' => (
    is => 'ro',
    handles => ['future'],
);

has 'is_connected' => (
    is => 'rw',
);

around BUILDARGS => sub( $orig, $class, %args ) {
    $args{ _log } = delete $args{ 'log' };
    $class->$orig( %args )
};

=back

=head2 C<< ->future >>

    my $f = $driver->future();

Returns a backend-specific generic future

=head2 C<< ->endpoint >>

    my $url = $driver->endpoint();

Returns the URL endpoint to talk to for the connected tab

=cut

has 'endpoint' => (
    is => 'rw', # actually, it isn't really rw, but set-once
);

=head2 C<< ->add_listener >>

    my $l = $driver->add_listener(
        'Page.domContentEventFired',
        sub {
            warn "The DOMContent event was fired";
        },
    );

    # ...

    undef $l; # stop listening

Adds a callback for the given event name. The callback will be removed once
the return value goes out of scope.

=cut

sub add_listener( $self, $event, $callback ) {
    my $listener = Chrome::DevToolsProtocol::EventListener->new(
        protocol => $self,
        callback => $callback,
        event    => $event,
    );
    $self->listener->{ $event } ||= [];
    push @{ $self->listener->{ $event }}, $listener;
    weaken $self->listener->{ $event }->[-1];
    $listener
}

=head2 C<< ->remove_listener >>

    $driver->remove_listener($l);

Explicitly remove a listener.

=cut

sub remove_listener( $self, $listener ) {
    # $listener->{event} can be undef during global destruction
    if( my $event = $listener->event ) {
        my $l = $self->listener->{ $event } ||= [];
        @{$l} = grep { $_ != $listener }
                grep { defined $_ }
                @{$self->listener->{ $event }};
        # re-weaken our references
        for (0..$#$l) {
            weaken $l->[$_];
        };
    };
}

=head2 C<< ->log >>

    $driver->log('debug', "Warbling doodads", { doodad => 'this' } );

Log a message

=cut

sub log( $self, $level, $message, @args ) {
    my $logger = $self->_log;
    if( !@args ) {
        $logger->$level( $message )
    } else {
        my $enabled = "is_$level";
        $logger->$level( join " ", $message, Dumper @args )
            if( $logger->$enabled );
    };
}

=head2 C<< ->connect >>

    my $f = $driver->connect()->get;

Asynchronously connect to the Chrome browser, returning a Future.

=cut

sub connect( $self, %args ) {
    my $s = $self;
    weaken $s;
    # If we are still connected to a different tab, disconnect from it
    if( $self->transport and ref $self->transport and $self->transport->type ne 'pipe') {
        $self->transport->close();
    };
    # Kick off the connect
    my $endpoint;
    $args{ writer_fh } //= $self->writer_fh;
    $args{ reader_fh } //= $self->reader_fh;
    $args{ endpoint } //= $self->endpoint;
    if( $args{ writer_fh } and $args{ reader_fh }) {
        # Pipe connection
        $args{ transport } ||= 'Chrome::DevToolsProtocol::Transport::Pipe';
        $endpoint = {
            reader_fh => $args{ reader_fh },
            writer_fh => $args{ writer_fh },
        };

    } elsif( $args{ endpoint }) {
        $endpoint = $args{ endpoint } || $self->endpoint;
        $self->log('trace', "Using endpoint $endpoint");
    };

    my $got_endpoint;
    if( ! $endpoint ) {
        if( ! $self->port ) {
            die "Can't connect without knowing the port?! " . $self->port;
        };
        $got_endpoint = $self->version_info()->then(sub( $info ) {
            $self->log('debug', "Found webSocket URL", $info );
            #$self->tab( $info );
            return Future->done( $info->{webSocketDebuggerUrl} );
        });

    } else {
        $got_endpoint = Future->done( $endpoint );
        if( ! ref $endpoint ) {
            # We need to somehow find the tab id for our tab, so let's fake it:
            $endpoint =~ m!/([^/]+)$!
                or die "Couldn't find tab id in '$endpoint'";
            $self->{tab} = {
                targetId => $1,
            };
        };
    };
    $got_endpoint = $got_endpoint->then(sub($endpoint) {
        $self->{ endpoint } = $endpoint;
        return Future->done( $endpoint );
    })->catch(sub(@args) {
        #croak @args;
        Future->fail( @args );
    });
    my $transport = delete $args{ transport }
                    || $self->transport
                    || 'Chrome::DevToolsProtocol::Transport';
    if( ! ref $transport ) { # it's a classname
        (my $transport_module = $transport) =~ s!::!/!g;
        $transport_module .= '.pm';
        require $transport_module;
        $self->{transport} = $transport->new;
        $transport = $self->{transport};
    };
    return $transport->connect( $self, $got_endpoint, sub {
        if( $s ) {
            $s->log( @_ )
        }
        #else {
        #    # We are in cleanup somewhere?!
        #    warn "@_";
        #}
    } )
    #->on_ready(sub {
    #    use Data::Dumper;
    #    warn Dumper \@_;
    #})
    ->on_done(sub {
        $s->is_connected(1);
    });
};

=head2 C<< ->close >>

    $driver->close();

Shut down the connection to Chrome

=cut

sub close( $self ) {
    if( my $t = $self->transport) {
        if( ref $t ) {
            undef $self->{transport};
            $t->close();
        };
    };
};

=head2 C<< ->sleep >>

    $driver->sleep(0.2)->get;

Sleep for the amount of seconds in an event-loop compatible way

=cut

sub sleep( $self, $seconds ) {
    $self->transport->sleep($seconds);
};

sub DESTROY( $self ) {
    delete $self->{ua};
    $self->close;
}

=head2 C<< ->one_shot >>

    my $f = $driver->one_shot('Page.domContentEventFired')->get;

Returns a future that resolves when the event is received

=cut

sub one_shot( $self, @events ) {
    my $result = $self->transport->future;
    my $ref = $result;
    weaken $ref;
    my %events;
    undef @events{ @events };
    push @{ $self->_one_shot }, { events => \%events, future => \$ref };
    $result
};

my %stack;
my $r;
sub on_response( $self, $connection, $message ) {
    my $response = eval { $self->json->decode( $message ) };
    if( $@ ) {
        $self->log('error', $@ );
        warn $message;
        return;
    };

    if( ! exists $response->{id} ) {
        # Generic message, dispatch that:
        if( my $error = $response->{error} ) {
            $self->log('error', "Error response from Chrome", $error );
            return;
        };

        (my $handler) = grep { exists $_->{events}->{ $response->{method} } and ${$_->{future}} } @{ $self->_one_shot };
        my $handled;
        if( $handler ) {
            $self->log( 'trace', "Dispatching one-shot event", $response );
            ${ $handler->{future} }->done( $response );

            # Remove the handler we just invoked
            @{ $self->_one_shot } = grep { $_ and ${$_->{future}} and $_ != $handler } @{ $self->_one_shot };

            $handled++;
        };

        if( my $listeners = $self->listener->{ $response->{method} } ) {
            @$listeners = grep { defined $_ } @$listeners;
            if( $self->_log->is_trace ) {
                if( $response->{method} ne 'Target.receivedMessageFromTarget' ) {
                    $self->log( 'trace', "Notifying listeners", $response );
                };
            } else {
                if( $response->{method} ne 'Target.receivedMessageFromTarget' ) {
                    $self->log( 'debug', sprintf "Notifying listeners for '%s'", $response->{method} );
                };
            };
            for my $listener (@$listeners) {
                eval {
                    $listener->notify( $response );
                };
                $self->log('error', $@) if $@;
                warn $@ if $@;
            };
            # re-weaken our references
            for (0..$#$listeners) {
                weaken $listeners->[$_]
                    if not isweak $listeners->[$_];
            };
            if( $response->{method} ne 'Target.receivedMessageFromTarget' ) {
                $self->log('trace', "Message handled", $response);
            };

            $handled++;
        };

        if( $self->on_message ) {
            if( $self->_log->is_trace ) {
                $self->log( 'trace', "Dispatching", $response );
            } else {
                my $frameId = $response->{params}->{frameId};
                my $requestId = $response->{params}->{requestId};
                if( $frameId || $requestId ) {
                    $self->log( 'debug', sprintf "Dispatching '%s' (%s:%s)", $response->{method}, $frameId || '-', $requestId || '-');
                } else {
                    $self->log( 'debug', sprintf "Dispatching '%s'", $response->{method} );
                };
            };
            $self->on_message->( $response );

            $handled++;
        };

        if( ! $handled ) {
            if( $self->_log->is_trace ) {
                $self->log( 'trace', "Ignored message", $response );
            } else {
                my $frameId = $response->{params}->{frameId};
                my $requestId = $response->{params}->{requestId};
                if( $frameId || $requestId ) {
                    $self->log( 'debug', sprintf "Ignoring '%s' (%s:%s)", $response->{method}, $frameId || '-', $requestId || '-');
                } else {
                    $self->log( 'debug', sprintf "Ignoring '%s'", $response->{method} );
                };
            };

        };
    } else {

        my $id = $response->{id};
        my $receiver = delete $self->{receivers}->{ $id };

        if( ! $receiver) {
            $self->log( 'debug', "Ignored response to unknown receiver", $response )

        } elsif( $response->{error} ) {
            $self->log( 'debug', "Replying to error $response->{id}", $response );
            $receiver->die( join "\n", $response->{error}->{message},$response->{error}->{data} // '',$response->{error}->{code} // '');
        } else {
            $self->log( 'trace', "Replying to $response->{id}", $response );
            $receiver->done( $response->{result} );
        };
    };
}

sub next_sequence( $self ) {
    my( $val ) = $self->current_sequence;
    $self->sequence_number( $val+1 );
    $val
};

sub current_sequence( $self ) {
    $self->sequence_number
};

sub build_url( $self, %options ) {
    my $url;
    if( ! ($options{ host } || $options{ port })
        and $self->{endpoint}) {
        # recycle our endpoint if we have it
        $url = URI->new($self->{ endpoint });
        $url->scheme('http');
        $url->path('json');
        $url = "$url";
    } else {
        $url = URI->new('json', 'http');
        $url->port( $self->port );
        $url->host( $self->host );
        $url = "$url";
    };
    $url .= '/' . $options{domain} if $options{ domain };
    $url
};

=head2 C<< $chrome->json_get >>

    my $data = $driver->json_get( 'version' )->get;

Requests an URL and returns decoded JSON from the future

=cut

sub json_get($self, $domain, %options) {
    my $url = $self->build_url( domain => $domain, %options );
    $self->log('trace', "Fetching JSON from $url");
    my $req = $self->ua->http_get( $url );
    $req->then( sub( $payload, $headers ) {
        $self->log('trace', "JSON response", $payload);
        Future->done( $self->json->decode( $payload ))
    });
};

sub _send_packet( $self, $response, $method, %params ) {
    my $id = $self->next_sequence;
    if( $response ) {
        $self->{receivers}->{ $id } = $response;
    };

    my $payload = eval {
        $self->json->encode({
            id     => 0+$id,
            method => $method,
            params => \%params
        });
    };
    if( my $err = $@ ) {
        $self->log('error', $@ );
    };

    $self->log( 'trace', "Sent message", $payload );
    my $result;
    try {
        $result = $self->transport->send( $payload );
    } catch {
        $self->log('error', $_ );
        $result = Future->fail( $_ );
    };
    return $result
}

=head2 C<< $chrome->send_packet >>

  $chrome->send_packet('Page.handleJavaScriptDialog',
      accept => JSON::true,
  );

Sends a JSON packet to the remote end

=cut

sub send_packet( $self, $topic, %params ) {
    $self->_send_packet( undef, $topic, %params )
}

=head2 C<< $chrome->send_message >>

  my $future = $chrome->send_message('DOM.querySelectorAll',
      selector => 'p',
      nodeId => $node,
  );
  my $nodes = $future->get;

This function expects a response. The future will not be resolved until Chrome
has sent a response to this query.

=cut

sub send_message( $self, $method, %params ) {
    my $response = $self->future;
    # We add our response listener before we've even sent our request to
    # Chrome. This ensures that no amount of buffering etc. will make us
    # miss a reply from Chrome to a request
    $self->_send_packet( $response, $method, %params )->retain;
    $response
}

=head2 C<< $chrome->callFunctionOn >>

=cut

sub callFunctionOn( $self, $function, %options ) {
    $self->send_message('Runtime.callFunctionOn',
        functionDeclaration => $function,
        returnByValue => JSON::true,
        arguments => $options{ arguments },
        objectId => $options{ objectId },
        %options
    )
};

=head2 C<< $chrome->evaluate >>

=cut

sub evaluate( $self, $string, %options ) {
    $self->send_message('Runtime.evaluate',
        expression => $string,
        returnByValue => JSON::true,
        %options
    )
};

=head2 C<< $chrome->eval >>

    my $result = $chrome->eval('2+2');

Evaluates a Javascript string and returns the result.

=cut

sub eval( $self, $string ) {
    $self->evaluate( $string )->then(sub( $result ) {
        Future->done( $result->{result}->{value} )
    });
};

=head2 C<< $chrome->version_info >>

    print $chrome->version_info->get->{"Protocol-Version"};

Returns the implemented ChromeDevTooslProtocol protocol version.

=cut

sub version_info($self) {
    $self->json_get( 'version' )->then( sub( $payload ) {
        Future->done( $payload );
    });
};

=head2 C<< $chrome->protocol_version >>

    print $chrome->protocol_version->get;

=cut

sub protocol_version($self) {
    $self->version_info->then( sub( $payload ) {
        Future->done( $payload->{"Protocol-Version"});
    });
};

=head2 C<< $target->getVersion >>

Returns information about the Chrome instance we are connected to.

=cut

sub getVersion( $self ) {
    $self->send_message( 'Browser.getVersion' )
}

=head2 C<< $chrome->get_domains >>

    my $schema = $chrome->get_domains->get;

Returns the topics of this Chrome DevToolsProtocol implementation.

=cut

sub get_domains( $self ) {
    $self->send_message('Schema.getDomains');
}

=head2 C<< $chrome->list_tabs >>

  my @tabs = $chrome->list_tabs->get();

=cut

sub list_tabs( $self, $type = 'page' ) {
    return $self->json_get('list')->then(sub( $info ) {
        @$info = grep { defined $type ? $_->{type} =~ /$type/i : 1 } @$info;
        Future->done( @$info );
    });
};

=head2 C<< $chrome->new_tab >>

    my $new_tab = $chrome->new_tab('https://www.google.com')->get;

=cut

sub new_tab( $self, $url=undef, %options ) {
    #my $u = $url ? '?' . $url : '';
    $self->log('trace', "Creating new tab");
    $self->createTarget( url => $url, %options );
};

=head2 C<< $chrome->activate_tab >>

    $chrome->activate_tab( $tab )->get

Brings the tab to the foreground of the application

=cut

sub activate_tab( $self, $tab ) {
    my $url = $self->build_url( domain => 'activate/' . $tab->{id} );
    $self->ua->http_get( $url );
};

=head2 C<< $chrome->close_tab >>

    $chrome->close_tab( $tab )->get

Closes the tab

=cut

sub close_tab( $self, $tab ) {
    my $url = $self->build_url( domain => 'close/' . $tab->{id} );
    $self->ua->http_get( $url, headers => { 'Connection' => 'close' } )
    ->catch(
        sub{ #use Data::Dumper; warn Dumper \@_;
             Future->done
        });
};

=head2 C<< $chrome->getTargets >>

    my @targets = $chrome->getTargets->get;

Gets the list of available targets

=cut

sub getTargets( $self ) {
    $self->send_message('Target.getTargets')->then(sub( $info ) {
        #use Data::Dumper; warn Dumper $info;
        Future->done( @{$info->{targetInfos}})
    });
}

=head2 C<< $target->getTargetInfo >>

    my $info = $chrome->getTargetInfo( $targetId )->get;
    print $info->{title};

Returns information about the current target

=cut

sub getTargetInfo( $self, $targetId=undef ) {
    $self->send_message('Target.getTargetInfo',
        maybe targetId => $targetId
    )->then(sub( $info ) {
            Future->done( $info->{targetInfo})
    });
}

=head2 C<< $target->createTarget >>

    my $targetId = $chrome->createTarget(
        url => 'about:blank',
        width => 1280,
        height => 800,
        newWindow => JSON::false,
        background => JSON::false,
    )->get;
    print $targetId;

Creates a new target, optionally in a new window

=cut

sub createTarget( $self, %options ) {
    $options{ url } //= 'about:blank';
    $self->send_message('Target.createTarget',
        %options )->then(sub( $info ) {
            Future->done( $info->{targetId})
    });
}

=head2 C<< $target->attachToTarget >>

    my $sessionId = $chrome->attachToTarget(
        targetId => $targetId,
    )->get;
    print $sessionId;

Attaches to the target so we receive events generated by the target

=cut

sub attachToTarget( $self, %options ) {
    $self->send_message('Target.attachToTarget',
        %options )->then(sub( $info ) {
            Future->done( $info->{sessionId})
    });
}

=head2 C<< $target->closeTarget >>

    my $targetId = $chrome->closeTarget(
        targetId => $targetId
    )->get;

Creates a new target

=cut

sub closeTarget( $self, %options ) {
    $self->send_message('Target.closeTarget',
        %options )
}

=head2 C<< $target->getWindowForTarget >>

    my $info = $chrome->getWindowForTarget( $targetId )->get;
    print $info->{windowId};

Returns information about the window of the current target

=cut

sub getWindowForTarget( $self, $targetId ) {
    $self->send_message('Browser.getWindowForTarget',
        targetId => $targetId
    );
}

=head2 C<< $chrome->getBrowserContexts >>

    my @browserContextIds = $chrome->getBrowserContexts->get;

Gets the list of available browser contexts. These are separate sets of user
cookies etc.

=cut

sub getBrowserContexts( $self ) {
    $self->send_message('Target.getBrowserContexts')->then(sub( $info ) {
        #use Data::Dumper; warn Dumper $info;
        Future->done( @{$info->{browserContextIds}})
    });
}


package
    Chrome::DevToolsProtocol::EventListener;
use strict;
use Moo;
use Carp 'croak';
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

our $VERSION = '0.66';

has 'protocol' => (
    is => 'ro',
    weak_ref => 1,
);

has 'callback' => (
    is => 'ro',
);

has 'event' => (
    is => 'ro',
);

around BUILDARGS => sub( $orig, $class, %args ) {
    croak "Need an event" unless $args{ event };
    croak "Need a callback" unless $args{ callback };
    croak "Need a DevToolsProtocol in protocol" unless $args{ protocol };
    return $class->$orig( %args )
};

sub notify( $self, @info ) {
    $self->callback->( @info )
}

sub unregister( $self ) {
    $self->protocol->remove_listener( $self )
        if $self->protocol; # it's a weak ref so it might have gone away already
    undef $self->{protocol};
}

sub DESTROY {
    $_[0]->unregister
}

1;

=head1 SEE ALSO

The inofficial Chrome debugger API documentation at
L<https://github.com/buggerjs/bugger-daemon/blob/master/README.md#api>

Chrome DevTools at L<https://chromedevtools.github.io/devtools-protocol/1-2>

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the Github bug queue at
L<https://github.com/Corion/WWW-Mechanize-Chrome/issues>

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2021 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
