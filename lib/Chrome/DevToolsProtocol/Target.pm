package Chrome::DevToolsProtocol::Target;
use 5.010; # for //
use strict;
use warnings;
use Moo;
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

our $VERSION = '0.35';
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

=item B<log>

A premade L<Log::Log4perl> object to act as logger

=cut

has 'receivers' => (
    is => 'ro',
    default => sub { {} },
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
    handles => [qw[future sleep endpoint close log _log version_info protocol_version
        getTargets
    ]],
);

has 'targetId' => (
    is => 'ro',
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

=head2 C<< ->connect >>

    my $f = $driver->connect()->get;

Asynchronously connect to the Chrome browser, returning a Future.

=cut

sub connect( $self, %args ) {
    # ... do we need to do anything here?!
    $self->{l} = $self->transport->add_listener('Target.receivedMessageFromTarget', sub {
        #use Data::Dumper;
        #warn Dumper \@_;
        my $payload = $_[0]->{params}->{message};
        $self->on_response( undef, $payload );
    });
    #warn Dumper $self->{l};
    Future->done()
};

=head2 C<< ->close >>

    $driver->close();

Shut down the connection to Chrome

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

        if( $self->on_message ) {
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
    croak "$self can't build URLs";
};

=head2 C<< $chrome->json_get >>

    my $data = $driver->json_get( 'version' )->get;

Requests an URL and returns decoded JSON from the future

=cut

sub json_get($self, $domain, %options) {
    croak "$self can't GET JSON data";
};

sub _send_packet( $self, $response, $method, %params ) {
    my $id = $self->next_sequence;
    if( $response ) {
        $self->{receivers}->{ $id } = $response;
    };

    my $s = $self;
    weaken $s;
    $response = $self->future->then(sub {
        $s->on_message( @_ );
    });

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
        # XXX this is half right - we get an ack when the message was accepted
        #     but we want to send the real reply when it comes back from the
        #     real target...
        $result = $self->transport->_send_packet(
            $response,
            'Target.sendMessageToTarget',
            message => $payload,
            targetId => $self->targetId
        );
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
    my $f;
    $f = $self->_send_packet( $response, $method, %params );
    $f->on_ready( sub { undef $f });
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

=head2 C<< $chrome->version_info >>

    print $chrome->version_info->get->{"Protocol-Version"};

=head2 C<< $chrome->protocol_version >>

    print $chrome->protocol_version->get;

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

=head2 C<< $chrome->close_tab >>

    $chrome->close_tab( $tab )->get

Closes the tab

=cut

sub close_tab( $self, $tab ) {
    croak "Won't close tabs, even though I could";
    my $url = $self->build_url( domain => 'close/' . $tab->{id} );
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

=head2 C<< $target->createTarget >>

    my $targetId = $chrome->createTarget(
        url => 'about:blank',
        width => 1280,
        height => 800,
        newWindow => JSON::false,
        background => JSON::false,
    )->get;
    print $targetId;

Creates a new target

=cut

sub createTarget( $self, %options ) {
    $options{ url } //= 'about:blank';
    $self->transport->send_message('Target.createTarget',
        %options )->then(sub( $info ) {
            Future->done( $info->{targetId})
    });
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
