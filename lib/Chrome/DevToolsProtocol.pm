package Chrome::DevToolsProtocol;
use strict;
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

use vars qw<$VERSION>;
$VERSION = '0.01';

# DOM access
# https://chromedevtools.github.io/devtools-protocol/tot/DOM/
# http://localhost:9222/json

sub _build_log( $self ) {
    require Log::Log4perl;
    Log::Log4perl->get_logger(__PACKAGE__);
}

sub new($class, %args) {
    my $self = bless \%args => $class;

    # Set up defaults
    $args{ host } ||= 'localhost';
    $args{ port } ||= 9222;
    $args{ json } ||= JSON->new;
    $args{ ua } ||= Future::HTTP->new;
    $args{ sequence_number } ||= 0;
    $args{ tab } ||= undef;
    $args{ log } ||= $self->_build_log;

    $args{ receivers } ||= {};
    $args{ on_message } ||= undef;
    $args{ one_shot } ||= [];

    $self
};

sub host( $self ) { $self->{host} }
sub port( $self ) { $self->{port} }
sub endpoint( $self ) {
    $self->tab
        and $self->tab->{webSocketDebuggerUrl}
}
sub json( $self ) { $self->{json} }
sub ua( $self ) { $self->{ua} }
sub tab( $self ) { $self->{tab} }
sub transport( $self ) { $self->{transport} }
sub future( $self ) { $self->transport->future }
sub on_message( $self, $new_message=0 ) {
    if( $new_message ) {
        $self->{on_message} = $new_message
    } elsif( ! defined $new_message ) {
        $self->{on_message} = undef
    };
    $self->{on_message}
}

sub log( $self, $level, $message, @args ) {
    my $logger = $self->{log};
    if( !@args ) {
        $logger->$level( $message )
    } else {
        my $enabled = "is_$level";
        $logger->$level( join " ", $message, Dumper @args )
            if( $logger->$enabled );
    };
}

sub connect( $self, %args ) {
    # If we are still connected to a different tab, disconnect from it
    if( $self->transport and ref $self->transport ) {
        $self->transport->close();
    };

    # Kick off the connect
    my $endpoint;
    if( $args{ endpoint }) {
        $endpoint = $args{ endpoint };

    } elsif( $args{ tab } and ref $args{ tab } eq 'HASH' ) {
        $endpoint = $args{ tab }->{webSocketDebuggerUrl};

    } elsif( exists $args{ new_tab } ) {
        $endpoint = undef;
        #$args{ tab } ||= 0;

    } elsif( $args{ tab } and $args{ tab } =~ /^\d+$/) {
        $endpoint = undef;

    } else {
        $endpoint ||= $self->endpoint;
    };

    my $got_endpoint;
    if( ! $endpoint ) {
        if( $args{ new_tab }) {
            $got_endpoint = $self->new_tab()->then(sub( $info ) {
                $self->log('debug', "Created new tab", $info );
                $self->{tab} = $info;
                return Future->done( $info->{webSocketDebuggerUrl} );
            });

        } elsif( defined $args{ tab } and $args{ tab } =~ /^\d+$/ ) {
            $got_endpoint = $self->list_tabs()->then(sub( @tabs ) {
                $self->log('debug', "Attached to tab $args{tab}", @tabs );
                $self->{tab} = $tabs[ $args{ tab }];
                return Future->done( $self->{tab}->{webSocketDebuggerUrl} );
            });

        } elsif( ref $args{ tab } eq 'Regexp') {
            # Let's assume that the tab is a regex:

            $got_endpoint = $self->list_tabs()->then(sub( @tabs ) {
                (my $tab) = grep { $_->{title} =~ /$args{ tab }/ } @tabs;

                if( ! $tab ) {
                    croak "Couldn't find a tab matching /$args{ tab }/";
                };

                $self->{tab} = $tab;
                $self->log('debug', "Attached to tab $args{tab}", $tab );
                return Future->done( $self->{tab}->{webSocketDebuggerUrl} );
            });

        } elsif( ref $args{ tab } ) {
            # Let's assume that the tab is a tab object:
            $got_endpoint = $self->list_tabs()->then(sub( @tabs ) {
                (my $tab) = grep { $_->{id} eq $args{ tab }->{id}} @tabs;
                $self->{tab} = $tab;
                $self->log('debug', "Attached to tab $args{tab}", $tab );
                return Future->done( $self->{tab}->{webSocketDebuggerUrl} );
            });

        } elsif( $args{ tab } ) {
            # Let's assume that the tab is the tab id:
            $got_endpoint = $self->list_tabs()->then(sub( @tabs ) {
                (my $tab) = grep { $_->{id} eq $args{ tab }} @tabs;
                $self->{tab} = $tab;
                $self->log('debug', "Attached to tab $args{tab}", $tab );
                return Future->done( $self->{tab}->{webSocketDebuggerUrl} );
            });

        } else {
            # Attach to the first available tab we find
            $got_endpoint = $self->list_tabs()->then(sub( @tabs ) {
                (my $tab) = grep { $_->{webSocketDebuggerUrl} } @tabs;
                $self->log('debug', "Attached to some tab", $tab );
                $self->{tab} = $tab;
                return Future->done( $self->{tab}->{webSocketDebuggerUrl} );
            });
        };

    } else {
        $got_endpoint = Future->done( $endpoint );
        # We need to somehow find the tab id for our tab, so let's fake it:
        $endpoint =~ m!/([^/]+)$!
            or die "Couldn't find tab id in '$endpoint'";
        $self->{tab} = {
            id => $1,
        };
    };
    $got_endpoint = $got_endpoint->then(sub($endpoint) {
        $self->{ endpoint } = $endpoint;
        return Future->done( $endpoint );
    })->catch(sub(@args) {
        croak @args;
    });

    my $transport = delete $args{ transport } || 'Chrome::DevToolsProtocol::Transport';
    if( ! ref $transport ) { # it's a classname
        (my $transport_module = $transport) =~ s!::!/!g;
        $transport_module .= '.pm';
        require $transport_module;
        $self->{transport} = $transport->new;
        $transport = $self->{transport};
    };

    $transport->connect( $self, $got_endpoint, sub { $self->log( @_ ) } )
    ->then(sub( $tr ) {
        return Future->done( $tr )
    });
};

sub DESTROY( $self ) {
    delete $self->{ua};
    if( my $t = $self->transport) {
        $t->close();
    };
}

sub one_shot( $self, @events ) {
    my $result = $self->transport->future;
    my $ref = $result;
    weaken $ref;
    my %events;
    undef @events{ @events };
    push @{ $self->{one_shot} }, { events => \%events, future => \$ref };
    $result
};

sub on_response( $self, $connection, $message ) {
    my $response = $self->json->decode( $message );

    if( ! exists $response->{id} ) {
        # Generic message, dispatch that:

        (my $handler) = grep { exists $_->{events}->{ $response->{method} } and ${$_->{future}} } @{ $self->{one_shot}};
        if( $handler ) {
            $self->log( 'trace', "Dispatching one-shot event", $response );
            ${ $handler->{future} }->done( $response );
            
            # Remove the handler we just invoked
            @{ $self->{one_shot}} = grep { $_ and ${$_->{future}} and $_ != $handler } @{ $self->{one_shot}};

        } elsif( $self->on_message ) {
            $self->log( 'trace', "Dispatching message", $response );
            $self->on_message->( $response );

        } else {
            $self->log( 'trace', "Ignored message", $response )
        };
    } else {

        my $id = $response->{id};
        my $receiver = delete $self->{receivers}->{ $id };

        if( ! $receiver) {
            $self->log( 'debug', "Ignored response to unknown receiver", $response )

        } elsif( $response->{error} ) {
            $self->log( 'debug', "Replying to error $response->{id}", $response );
            $receiver->die( join "\n", $response->{error}->{message},$response->{error}->{data},$response->{error}->{code} );
        } else {
            $self->log( 'debug', "Replying to $response->{id}", $response );
            $receiver->done( $response->{result} );
        };
    };
}

sub next_sequence( $self ) {
    $self->{sequence_number}++
};

sub current_sequence( $self ) {
    $self->{sequence_number}
};

sub build_url( $self, %options ) {
    $options{ host } ||= $self->{host};
    $options{ port } ||= $self->{port};
    my $url = sprintf "http://%s:%s/json", $options{ host }, $options{ port };
    $url .= '/' . $options{domain} if $options{ domain };
    $url
};

=head2 C<< $chrome->json_get >>

=cut

sub json_get($self, $domain, %options) {
    my $url = $self->build_url( domain => $domain, %options );
    $self->ua->http_get( $url )->then( sub( $payload, $headers ) {
        Future->done( $self->json->decode( $payload ))
    });
};

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
    my $id = $self->next_sequence;
    my $payload = $self->json->encode({
        id => $id,
        method => $method,
        params => \%params
    });

    my $response = $self->future;
    $self->log( 'trace', "Sent message", $payload );
    $self->transport->send( $payload );
    $self->{receivers}->{ $id } = $response;
    $response
}

=head2 C<< $chrome->evaluate >>

=cut

sub evaluate( $self, $string ) {
    $self->send_message('Runtime.evaluate',
        expression => $string,
        returnByValue => JSON::true
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

=head2 C<< $chrome->get_domains >>

=cut

sub get_domains( $self ) {
    $self->send_message('Schema.getDomains');
}

=head2 C<< $chrome->list_tabs >>

  my @tabs = $chrome->list_tabs->get();

=cut

sub list_tabs( $self, $type = 'page' ) {
    return $self->json_get('list')->then(sub( $info ) {
        @$info = grep { defined $type ? $_->{type} eq $type : 1 } @$info;
        return Future->done( @$info );
    });
};

=head2 C<< $chrome->new_tab >>

    my $new_tab = $chrome->new_tab('https://www.google.com')->get;

=cut

sub new_tab( $self, $url=undef ) {
    my $u = $url ? '?' . $url : '';
    $self->json_get('new' . $u)
};

=head2 C<< $chrome->activate_tab >>

=cut

sub activate_tab( $self, $tab ) {
    my $url = $self->build_url( domain => 'activate/' . $tab->{id} );
    $self->ua->http_get( $url );
};

=head2 C<< $chrome->close_tab >>

=cut

sub close_tab( $self, $tab ) {
    my $url = $self->build_url( domain => 'close/' . $tab->{id} );
    $self->ua->http_get( $url, headers => { 'Connection' => 'close' } )
    ->catch(
        sub{ use Data::Dumper; warn Dumper \@_; Future->done }
    );
};

1;

=head1 SEE ALSO

Chrome DevTools at L<https://chromedevtools.github.io/devtools-protocol/1-2>

=cut