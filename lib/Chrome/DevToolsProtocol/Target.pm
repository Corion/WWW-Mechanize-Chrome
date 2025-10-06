package Chrome::DevToolsProtocol::Target;
use 5.020; # for signatures
use strict;
use warnings;
use Moo 2;

use experimental 'signatures';

use Future;
use Future::HTTP;
use Carp qw(croak carp);
use JSON;
use Data::Dumper;
use Chrome::DevToolsProtocol::Transport;
use Scalar::Util 'weaken', 'isweak';
use Try::Tiny;
use PerlX::Maybe;

with 'MooX::Role::EventEmitter';

our $VERSION = '0.73';
our @CARP_NOT;

=head1 NAME

Chrome::DevToolsProtocol::Target - wrapper for talking to a page in a Target

=head1 SYNOPSIS

    # Usually, WWW::Mechanize::Chrome automatically creates a driver for you
    my $driver = Chrome::DevToolsProtocol::Target->new(
        transport => $target,
    );
    $driver->connect( new_tab => 1 )->get

=head1 METHODS

=head2 C<< ->new( %args ) >>

    my $driver = Chrome::DevToolsProtocol::Target->new(
        transport => $target,
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


=item B<json>

The JSON decoder used

=cut

has 'json' => (
    is => 'ro',
    default => sub { JSON->new },
);

=item B<tab>

Which tab to reuse (if any)

=cut

has 'tab' => (
    is => 'rw',
);

=item B<autoclose>

Close the tab when the object goes out of scope

=cut

has 'autoclose' => (
    is => 'rw',
);

=item B<log>

A premade L<Log::Log4perl> object to act as logger

=cut

has 'receivers' => (
    is => 'ro',
    default => sub { {} },
);

=item B<app>

If launching Chrome in app mode, connect to this page

=cut

has 'app' => (
    is => 'ro',
    default => sub { undef },
);

=back

=head1 EVENTS

=over 4

=item B<message>

A callback invoked for every message

=cut

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
    handles => [qw[future sleep endpoint log _log
        getTargets
    ]],
);

# This is maybe deprecated?
has 'targetId' => (
    is => 'rw',
);

has 'sessionId' => (
    is => 'rw',
);

has 'browserContextId' => (
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
    return $listener
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

=head2 C<< ->connect >>

    my $f = $driver->connect()->get;

Asynchronously connect to the Chrome browser, returning a Future.

=cut

sub connect( $self, %args ) {
    my $s = $self;
    weaken $s;
    my $done = $self->transport->is_connected
        ? Future->done
        : $self->transport->connect();

    $done = $done->then(sub {
        $s->{l} = $s->transport->add_listener('Target.receivedMessageFromTarget', sub {
            if( $s ) {
                #$s->log( 'trace', '(target) receivedMessage', $_[0] );
                my $id = $s->targetId;
                my $sid = $s->sessionId;
                if( exists $_[0]->{params}->{sessionId}
                    and $sid
                    and $_[0]->{params}->{sessionId} eq $sid) {
                    my $payload = $_[0]->{params}->{message};
                    $s->on_response( undef, $payload );
                } elsif( !$id
                         or ($_[0]->{params}->{targetId} and $id eq $_[0]->{params}->{targetId})) {
                    my $payload = $_[0]->{params}->{message};
                    $s->on_response( undef, $payload );
                };
            #} else {
            #    warn "Target listener for answers has gone away";
            #    use Data::Dumper; warn Dumper($_[0]);
            };
        });
        Future->done;
    });

    if( $args{ new_tab } ) { # should be renamed "separate_session"
        if( $args{ separate_session }) {
            # Set up a new browser context
            $done = $done->then( sub { $s->transport->send_message('Target.createBrowserContext')})
            ->then( sub( $info ) {
                $s->browserContextId( $info->{browserContextId} );
                Future->done();
            });

        } else {
            # Find an existing browser context and use that one
            $done = $done->then( sub { $s->getTargets })
            ->then( sub( @targets ) {
                #$self->browserContextId( $targets[0]->{browserContextId} );
                Future->done();
            });
        }

        $done = $done->then(sub {
            my $id = $s->browserContextId;
            $s->createTarget(
                url => $args{ start_url } || 'about:blank',
                maybe browserContextId => $id,
            );
        })->then(sub( $info ) {
            $s->tab( $info );
            $s->attach( $info->{targetId} )
        });

    } elsif( ref $args{ tab } eq 'Regexp') {
        # Let's assume that the tab is a regex:

        $done = $done->then(sub {
            $s->getTargets()
        })->then(sub( @tabs ) {
            (my $tab) = grep { $_->{title} =~ /$args{ tab }/ } @tabs;

            if( ! $tab ) {
                $s->log('warn', "Couldn't find a tab matching /$args{ tab }/");
                croak "Couldn't find a tab matching /$args{ tab }/";
            } elsif( ! $tab->{targetId} ) {
                local @CARP_NOT = ('Future',@CARP_NOT);
                croak "Found the tab but it didn't have a targetId";
            };
            $s->tab( $tab );
            $s->attach( $tab->{targetId} )
        });

    } elsif( ref $args{ tab } ) {
        # Let's assume that the tab is a Target hash:
        my $tab = $args{ tab };
        $self->tab($tab);
        $done = $done->then(sub {
            $s->attach( $s->tab->{targetId});
        });

    } elsif( defined $args{ tab } and $args{ tab } =~ /^\d{1,5}$/ ) {
        $done = $done->then(sub {
            $s->getTargets()
        })->then(sub( @tabs ) {
            my $res;
            my @visible_tabs;
            if( $args{ app } // $self->app ) {
                @visible_tabs = grep { $_->{type} eq 'app' && $_->{targetId} } @tabs;
            } else {
                @visible_tabs = grep { $_->{type} eq 'page' && $_->{targetId} } @tabs;
            }
            if( ! @visible_tabs ) {
                $res = $s->createTarget(
                    url => $args{ start_url } || 'about:blank',
                );
            } else {
                $res = Future->done( $visible_tabs[$args{ tab }] );
            };
            $res = $res->then(sub($tab) {
                $s->tab( $tab );
                $s->attach( $s->tab->{targetId} );
            });
        });

    } elsif( $args{ tab } ) {
        # Let's assume that the tab is the tab id:
        $done = $done->then(sub {
            $s->getTargetInfo( $args{tab})
        })->then(sub( $tab ) {
            $s->tab($tab);
            $s->attach( $tab->{targetId});
        });

    } else {
            # Attach to the first available tab we find
        $done = $done->then(sub (@) {
            $s->getTargets()
        })->then(sub( @tabs ) {
            (my $tab) = grep { $_->{type} eq 'page' && $_->{targetId} } @tabs;
            $s->tab($tab);
            $s->attach( $tab->{targetId} )
        });
    };

    $done
};

=head2 C<< ->close >>

    $driver->close();

Shut down the connection to our tab and close it.

=cut

sub close( $self ) {
    if( my $t = $self->transport) {
        $t->closeTarget(targetId => $self->targetId );
    }
}

sub DESTROY( $self ) {
    if( $self->autoclose ) {
        $self->close->catch(sub {})->retain;
    }
};

=head2 C<< ->sleep >>

    $driver->sleep(0.2)->get;

Sleep for the amount of seconds in an event-loop compatible way

=head2 C<< ->one_shot >>

    my $f = $driver->one_shot('Page.domContentEventFired')->get;

Returns a future that resolves when the event is received

=cut

sub one_shot( $self, @events ) {
    my $result = $self->future;
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
                $self->log( 'trace', "Notifying listeners", $response );
            } else {
                $self->log( 'debug', sprintf "Notifying listeners for '%s'", $response->{method} );
            };
            for my $listener (@$listeners) {
                eval {
                    $listener->notify( $response );
                };
                warn $@ if $@;
            };
            # re-weaken our references
            for (0..$#$listeners) {
                weaken $listeners->[$_];
            };

            $handled++;
        };

        if( $self->has_subscribers('message') ) {
            if( $self->transport->_log->is_trace ) {
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
            $self->emit('message', $response );

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

        } elsif( $receiver eq 'ignore') {
            # silently ignore that reply

        } elsif( $response->{error} ) {
            $self->log( 'debug', "Replying to error $response->{id}", $response );
            # It would be nice if Future had ->croak(), so we could report
            # the error on the line that originally called us maybe
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
    croak "$self can't build URLs";
};

=head2 C<< $chrome->json_get >>

    my $data = $driver->json_get( 'version' )->get;

Requests an URL and returns decoded JSON from the future

=cut

sub json_get($self, $domain, %options) {
    croak "$self can't GET JSON data";
};

=head2 C<< $chrome->version_info >>

    print $chrome->version_info->get->{"protocolVersion"};

=cut

sub version_info( $self ) {
    $self->getVersion
}

=head2 C<< $chrome->protocol_version >>

    print $chrome->protocol_version->get;

=cut

sub protocol_version( $self ) {
    $self->getVersion->then(sub( $info ) {
        Future->done($info->{"protocolVersion"})
    })
}

sub _send_packet( $self, $response, $method, %params ) {
    my $id = $self->next_sequence;
    if( $response ) {
        $self->{receivers}->{ $id } = $response;
    };

    my $s = $self;
    weaken $s;

    my $payload = eval {
        $s->json->encode({
            id     => 0+$id,
            method => $method,
            params => \%params
        });
    };
    if( my $err = $@ ) {
        $s->log('error', $@ );
        $s->log('error', Dumper \%params );
    };

    $s->log( 'trace', "Sent message", $payload );
    my $result;
    try {
        # this is half right - we get an ack when the message was accepted
        # but we want to send the real reply when it comes back from the
        # real target. This is done in the listener for receivedMessageFromTarget
        #my $ignore = $s->future->retain;
        $result = $s->transport->_send_packet(
            #$ignore, # this one leads to a circular reference somewhere when using AnyEvent backends?!
            'ignore',
            'Target.sendMessageToTarget',
            message => $payload,
            targetId => $s->targetId,
            maybe sessionId => $s->sessionId,
        );
        $result->set_label('Target.sendMessageToTarget');
    } catch {
        $s->log('error', $_ );
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
    my $f = $self->_send_packet( $response, $method, %params )->retain;
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

=cut

sub eval( $self, $string ) {
    $self->evaluate( $string )->then(sub( $result ) {
        Future->done( $result->{result}->{value} )
    });
};

=head2 C<< $chrome->get_domains >>

=cut

sub get_domains( $self ) {
    $self->send_message('Schema.getDomains');
}

=head2 C<< $chrome->list_tabs >>

  my @tabs = $chrome->list_tabs->get();

=cut

sub list_tabs( $self, $type = 'page' ) {
    croak "Won't list tabs, even though I could";
};

=head2 C<< $chrome->new_tab >>

    my $new_tab = $chrome->new_tab('https://www.google.com')->get;

=cut

sub new_tab( $self, $url=undef ) {
    croak "Won't create tabs, even though I could";
};

=head2 C<< $chrome->activate_tab >>

    $chrome->activate_tab( $tab )->get

Brings the tab to the foreground of the application

=cut

sub activate_tab( $self, $tab ) {
    croak "Won't activate tabs, even though I could";
};

=head2 C<< $target->getTargetInfo >>

Returns information about the current target

=cut

sub getTargetInfo( $self, $targetId = $self->targetId ) {
    $self->transport->getTargetInfo( $targetId )->then(sub( $info ) {
        Future->done( $info )
    });
}

=head2 C<< $target->info >>

Returns information about the current target

=cut

sub info( $self ) {
    $self->getTargetInfo( $self->targetId )->get
}

=head2 C<< $target->title >>

Returns the title of the current target

=cut

sub title( $self ) {
    $self->getTargetInfo( $self->targetId )->get->{title}
}

=head2 C<< $target->getVersion >>

Returns information about the Chrome instance we are connected to.

=cut

sub getVersion( $self ) {
    $self->send_message( 'Browser.getVersion' )
}

=head2 C<< $target->createTarget >>

    my $info = $chrome->createTarget(
        url => 'about:blank',
        width => 1280,
        height => 800,
        newWindow => JSON::false,
        background => JSON::false,
    )->get;
    print $info->{targetId};

Creates a new target

=cut

sub createTarget( $self, %options ) {
    $options{ url } //= 'about:blank';
    $self->transport->send_message('Target.createTarget',
        %options )->then(sub( $info ) {
            Future->done( $info )
    });
}


=head2 C<< $target->attach >>

    $target->attach();

Attaches to the target set up in C<targetId> and C<sessionId>. If a targetId is
given, attaches to it and remembers the value.

=cut

sub attach( $self, $targetId=$self->targetId ) {
    my $s = $self;
    weaken $s;
    $self->targetId( $targetId );

    $self->{have_target_info} = $self->transport->one_shot('Target.attachedToTarget')->then(sub($r) {
    #    #$s->log('trace', "Attached to", $r );
        #use Data::Dumper; warn Dumper $r;
        #$s->browserContextId($r->{params}->{targetInfo}->{browserContextId});
    #    #$s->sessionId( $target->{sessionId});
    #    #$s->log('debug', "Attached to session $target->{sessionId}" );
    #    #undef $s->{have_session};
        return Future->done;
    })->retain;

    $self->transport->attachToTarget( targetId => $targetId )
    ->on_done(sub( $sessionId ) {
        $s->sessionId( $sessionId );
        $s->log('debug', "Attached to tab $targetId, session $sessionId" );
    });
};

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

Copyright 2010-2024 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
