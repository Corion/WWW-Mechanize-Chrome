#!perl
use strict;
use warnings;
use 5.020;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'say';
use File::Temp 'tempdir';
use Carp 'croak';

use Data::Dumper;
use WWW::Mechanize::Chrome;
use JSON;
use Log::Log4perl ':easy';
use List::Util 'mesh';
Log::Log4perl->easy_init($WARN);

my $mech = WWW::Mechanize::Chrome->new(
    data_directory => tempdir( CLEANUP => 1 ),
    headless => 1,
);
$mech->target->send_message('HeapProfiler.enable')->get;

#$mech->get('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
#$mech->get('https://www.youtube.com/embed/dQw4w9WgXcQ');

# Let's start with something simpler
$mech->get_local('heap-test-01.html');
my $chunk;
my $done = $mech->target->future;
my $collector = $mech->target->add_listener( 'HeapProfiler.addHeapSnapshotChunk', sub($message) {
    $chunk .= $message->{params}->{chunk};

    # We know that we're done if we receive a chunk with "]}" ?!
    if( $chunk =~ /\]\}$/ ) {
        $done->done($chunk);
    };
});

my $info =
$mech->target->send_message(
    'HeapProfiler.takeHeapSnapshot',
    captureNumericValue => JSON::true,
    treatGlobalObjectsAsRoots => JSON::true,
)->get;

#$mech->sleep(30);
my $heapdump = $done->get;
my $heap = decode_json($heapdump);

#use Data::Dumper;
#print Dumper $heap->{strings};

# Now, search the heap for an object containing our magic strings:
#
my %seen;
sub iterate($heap, $visit, $path='', $vis=$path) {
    # Check if we find the hash keys:
    if( ! $seen{ $vis }++ ) {
        print "$vis\n";
    };
    $visit->($heap, $path);
    if( ref $heap eq 'HASH' ) {
        for my $key (sort keys %$heap) {
            my $val = $heap->{$key};
            if( ref $val) {
                my $sub = "$path/$key";
                my $subvis = $sub;
                iterate( $val, $visit, $sub, $subvis );
            }
        }
    } elsif( ref $heap eq 'ARRAY' ) {
        for my $i (0..$#$heap) {
            my $val = $heap->[$i];
            if( ref $val) {
                my $sub = "$path\[$i\]";
                my $subvis = "$path\[.\]";
                iterate( $val, $visit, $sub, $subvis );
            }
        }
    };
}

sub find_string($heap, $value, $path='/strings') {
    my @res;
    iterate($heap->{strings}, sub($item, $path) {
        if( ref $item eq 'HASH' ) {
            if( grep { defined $_ and $_ =~ /$value/ } values %$item ) {
                my @keys = grep { defined $item->{$_} and $item->{$_} =~ $value } keys %$item;
                for my $k (sort @keys) {
                    push @res, { path => "$path/$k", value => $item->{k} };
                };
            };
        } elsif( ref $item eq 'ARRAY' ) {
            if( grep { defined $_ and $_ =~ /$value/ } @$item ) {
                my @indices = grep { defined $item->[$_] and $item->[$_] =~ $value } 0..$#$item;
                push @res, map +{ path => "$path\[$_]", value => $item->[$_] }, @indices;
            };
        }
    });
    @res
}

sub find_string_exact($heap, $value, $path='/strings') {
    my @res;
    iterate($heap->{strings}, sub($item, $path) {
        if( ref $item eq 'HASH' ) {
            if( grep { defined $_ and $_ =~ /$value/ } values %$item ) {
                my @keys = grep { defined $item->{$_} and $item->{$_} eq $value } keys %$item;
                for my $k (sort @keys) {
                    push @res, { path => "$path/$k", value => $item->{k} };
                };
            };
        } elsif( ref $item eq 'ARRAY' ) {
            if( grep { defined $_ and $_ =~ /$value/ } @$item ) {
                my @indices = grep { defined $item->[$_] and $item->[$_] eq $value } 0..$#$item;
                push @res, map +{ path => "$path\[$_]", value => $item->[$_] }, @indices;
            };
        }
    });
    @res
}

# Object variable:
my %node_field_index;
my %edge_field_index;
my $node_size = scalar @{ $heap->{snapshot}->{meta}->{node_fields} };
my $edge_size = scalar @{ $heap->{snapshot}->{meta}->{edge_fields} };
sub init_heap( $heap ) {
    $node_size = scalar @{ $heap->{snapshot}->{meta}->{node_fields} };
    $edge_size = scalar @{ $heap->{snapshot}->{meta}->{edge_fields} };
    #say "Node size: $node_size";
    #say "Edge size: $edge_size";


    my $f = $heap->{snapshot}->{meta}->{node_fields};
    %node_field_index = map {
        $f->[$_] => $_
    } 0..$#$f;

    $f = $heap->{snapshot}->{meta}->{edge_fields};
    %edge_field_index = map {
        $f->[$_] => $_
    } 0..$#$f;
}
init_heap($heap);

sub field_value( $heap, $type, $name, $values ) {
    my $f = $heap->{snapshot}->{meta}->{"${type}_fields"};
    (my $idx) = grep { $f->[$_] eq $name } @$f;
    die "Unknown field name '$name'" if ! defined $idx;

    my $field_type = $heap->{snapshot}->{meta}->{"$type\_types"}->{$idx};
    my $field_val  = $values->{$idx};

    if( ref $field_type and ref $field_type eq 'ARRAY' ) {
    } elsif( $field_type eq 'string' ) {
        return $heap->{strings}->[$field_val];
    } elsif( $field_type eq 'number' ) {
    } else {
        croak "Unknown field type '$field_type'";
    }
}

## Size of a node/edge
# These are stored as flat arrays and the names of the keys are stored
# in snapshot/meta/{node,edge}_fields
# each node has (currently) 7 fields
# each edge has (currently) 3 fields

sub edge_at_index( $heap, $idx ) {
    my $ofs = $idx * $edge_size;
    # Maybe return an arrayref here, later?
    return @{ $heap->{edges} }[ $ofs .. $ofs+($edge_size-1) ];
}

sub node_at_index( $heap, $idx ) {
    my $ofs = $idx * $node_size;
    @{ $heap->{nodes} }[ $ofs .. $ofs+($node_size-1) ];
}

sub node_by_id( $heap, $node_id ) {
    # Maybe some kind of caching here, as well, or gradually building
    # a hash out of/into the structure?!
    for my $idx ( 0..$heap->{snapshot}->{node_count}-1 ) {
        my $id = get_node_field($heap, $idx, 'id');
        #my $name = get_node_field($heap, $idx, 'name');
        #my $type = get_node_field($heap, $idx, 'type');
        #warn "$node_id:$idx: $id $name [$type]";
        if( $id == $node_id ) {
            return $idx
        };
    }
    croak "Unknown node id $node_id";
}

sub edge( $heap, $idx ) {
    my @vals = edge_at_index( $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{edge_fields}, \@vals
    }
}

sub full_edge( $heap, $idx ) {
    return +{
        _idx => $idx,
        map {
            $_ => get_edge_field( $heap, $idx, $_ )
        } @{ $heap->{snapshot}->{meta}->{edge_fields} }
    }
}

sub node( $heap, $idx ) {
    my @vals = node_at_index( $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{node_fields}, \@vals
    }
}

sub full_node( $heap, $idx ) {
    return +{
        _idx => $idx,
        map {
            $_ => get_node_field( $heap, $idx, $_ )
        } @{ $heap->{snapshot}->{meta}->{node_fields} }
    }
}

sub get_node_field($heap, $idx, $fieldname) {
    croak "Invalid node field name '$fieldname'"
        unless exists $node_field_index{ $fieldname };
    if( $idx > $heap->{snapshot}->{node_count}) {
        croak "Invalid node index '$idx'";
    };

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $node_field_index{ $fieldname };
    my $val = $heap->{nodes}->[$idx*$node_size+$fi];
    if( ! defined $val ) {
        warn "Node $idx.$fieldname: undefined"; # $idx*$node_size+$fi
    }

    my $ft = $heap->{snapshot}->{meta}->{node_types}->[$fi];
    if( ref $ft eq 'ARRAY' ) {
        $val = $ft->[$val]
    } elsif( $ft eq 'number' ) {
        # we use the value as-is
    } elsif( $ft eq 'string' ) {
        $val = $heap->{strings}->[$val]
        #croak "String-fetching for node types not implemented";
    } else {
        croak "Unknown node field type '$ft' for '$fieldname'";
    }

    return $val;
}

sub get_edge_field($heap, $idx, $fieldname) {
    croak "Invalid edge field name '$fieldname'"
        unless exists $edge_field_index{ $fieldname };

    if( $idx >= $heap->{snapshot}->{edge_count} ) {
        croak "Invalid edge index $idx, maximum is $heap->{snapshot}->{edge_count}";
    }

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $edge_field_index{ $fieldname };
    my $val = (edge_at_index( $heap, $idx ))[$fi];

    my $ft = $heap->{snapshot}->{meta}->{edge_types}->[$fi];
    if( ref $ft eq 'ARRAY' ) {
        $val = $ft->[$val]
    } elsif( $ft eq 'number' ) {
        # we use the value as-is
    } elsif( $ft eq 'node' ) {
        # we use the value as-is
    } elsif( $ft eq 'string' ) {
        $val = $heap->{strings}->[$val]
    } elsif( $ft eq 'string_or_number' ) {
        $val = $heap->{strings}->[$val]
    } else {
        croak "Unknown edge field type '$ft' for '$fieldname'";
    }
    return $val;
}

# Returns the edge_count field of a node
sub get_edge_count( $heap, $idx ) {
    return get_node_field( $heap, $idx, 'edge_count' )
}

sub filter_edges( $heap, $cb ) {
    my $edges = $heap->{edges};
    grep { $cb->($edges, $_) } 0..$heap->{snapshot}->{edge_count}-1
}

# idx
sub get_edge_target( $heap, $idx ) {
    my $v = get_edge_field( $heap, $idx, 'to_node' );
    return $v / $node_size
}

# "Parent" nodes?
sub edges_referencing_node( $heap, $node_idx ) {
    croak "Invalid node index $node_idx"
        if $node_idx >= $heap->{snapshot}->{node_count};
    filter_edges( $heap, sub($edges, $idx) {
        my $v = get_edge_target( $heap, $idx );
        if( ! defined $v ) {
            croak "Invalid edge index $idx!";
        };
        $v == $node_idx
    })
}

sub edge_ids_from_node( $heap, $node_idx ) {
    # Find where our node_id starts in the list of edges. For that, we need
    # to sum the edgecount of all previous nodes.
    # This should maybe later be cached/indexed so we don't always have
    # to rescan the whole array
    my $edge_offset = 0;
    for my $idx (0..$node_idx-1) {
        $edge_offset += get_node_field($heap,$idx,'edge_count');
    };
    my $edges = get_node_field($heap,$node_idx,'edge_count');
    return @{ $heap->{edges} }[$edge_offset..$edge_offset+$edges]
}

# "Child" nodes?
# idx -> full nodes
sub nodes_from_node( $heap, $node_idx ) {
    my @edges = edge_ids_from_node( $heap, $node_idx );
    my @node_idxs = map {
        get_edge_target( $heap, $_ );
    } @edges;
    return map { full_node( $heap, $_ ) } @node_idxs
}

sub nodes_with_string_id($heap,$string_id) {
    my $n = $heap->{nodes};
    my $str = $heap->{strings}->[$string_id];
    #croak "No node field index 'name' found"
    #    unless exists $node_field_index{'name'};
    #my $fi = $node_field_index{'name'};
    grep {
        get_node_field( $heap, $_, 'name') eq $str
        # $n->[$idx*$node_size+$fi] == $string_id;
    } 0..$heap->{snapshot}->{node_count}-1
}

#my @usage = find_string_exact($heap,'Rick Astley');
#my @usage = find_string_exact($heap,'structname');
#$usage[0]->{path} =~ /\[(\d+)\]/
#    or die "Weirdo path: '$usage[0]->{path}'";
#my $idx = $1;
#say "'structname' has string id $idx ($usage[0]->{path})";
#my @nodes = nodes_with_string_id( $heap, $idx );
#say "Nodes referencing that string: " . Dumper \@nodes;
#my $id = get_node_field( $heap, $nodes[0], 'id');
#my $idx = node_by_id($heap,$id);
#say "Edges referencing that node: " . Dumper [edges_referencing_node( $heap, $id )];
#say "Edges from that node: " . Dumper [map { full_edge( $heap, $_ ) } edge_ids_from_node( $heap, $idx )];
#say "Nodes from that node: " . Dumper [nodes_from_node( $heap, $idx )];

# strings <- edge
# strings <- node

#find_value($heap,'Astley');
#find_value($heap,'dQw4w9WgXcQ');

sub dump_node( $heap, $msg, @node_ids ) {
    my @nodes = map { full_node($heap,$_) }
                map { node_by_id( $heap, $_ ) } @node_ids;
    for my $n (@nodes) {
        my @edge_ids = edge_ids_from_node( $heap, $n->{_idx} );
        $n->{edges} = [map {full_edge($heap,$_)} @edge_ids ];
    };

    print "$msg: " . Dumper \@nodes;
}

sub _node_as_dot( $node ) {
    my $name = $node->{name} || "($node->{id})";
    return qq{$node->{id} [label = "$name ($node->{type})"]};
}

sub _edge_as_dot( $nid, $edge ) {
    # to_node is the _index_ of the first field of the node in the array!
    # NOT the index of the node...
    my $node_idx = $edge->{to_node} / $node_size;
    my $targ = get_node_field( $heap, $node_idx, 'id' );

    my $label = $edge->{name_or_index};
    if( $label =~ /^\d+$/ ) {
        $label = '';
    } else {
        $label = qq([label="$label"]);
    };

    return qq{$nid -> $targ$label};
}

sub dump_node_as_dot( $heap, $msg, @node_ids ) {
    my @nodes = map { full_node($heap,$_) }
                map { node_by_id( $heap, $_ ) }
                @node_ids;
    for my $n (@nodes) {
        my @edge_ids = edge_ids_from_node( $heap, $n->{_idx} );
        $n->{edges} = [map {full_edge($heap,$_)} @edge_ids ];
    };

    my %leaves;

    my %node_seen;
    for my $n (@nodes) {
        my $nid = $n->{id};
        next if $node_seen{ $nid }++;
        delete $leaves{ $nid };

        say _node_as_dot( $n );

        for my $e (@{$n->{edges}}) {
            my $node_idx = $e->{to_node}/$node_size;
            my $id = get_node_field( $heap, $node_idx, 'id');
            $leaves{ $id } = 1;
            say _edge_as_dot($n->{id}, $e);
        };
    };
    for my $nid (sort { $a <=> $b } keys %leaves) {
        my $n = full_node( $heap, node_by_id( $heap, $nid ));
        say _node_as_dot( $n );
    };
}

sub dump_nodes_with_string( $heap, $string ) {
    my @usage = find_string_exact($heap,$string);
    $usage[0]->{path} =~ /\[(\d+)\]/
        or die "Weirdo path: '$usage[0]->{path}'";
    my $idx = $1;
    dump_node( "Nodes using '$string'", nodes_with_string_id($heap, $idx) );
}

# This includes the nodes themselves!
sub reachable( $heap, $start, $depth=1 ) {
    my %reachable = map { $_ => 1 } @$start;
    my @curr = @$start;
    for my $d (1..$depth) {
        my %new;
        for my $nid (@curr) {
            my $idx = node_by_id( $heap, $nid );
            my @reachable = nodes_from_node( $heap, $idx );
            warn sprintf "%d new nodes directly reachable from source set", scalar @reachable;
            for my $r (@reachable) {
                if( !$reachable{ $r->{id}}) {
                    $new{ $r->{id} } = 1
                };
            };
        }
        @reachable{ keys %new } = values %new;
        @curr = sort { $a <=> $b } keys %new;
    };
    return sort { $a <=> $b } keys %reachable;
}

#for my $edge_idx (0..10000) {
#    my $e = full_edge($heap, $edge_idx);
#    if( $e->{type} eq 'property' ) {
#        say Dumper $e;
#    };
#}

#for my $e (0..10) {
#    my $edge = full_edge($heap,$e);
#    say _edge_as_dot( 0, $edge );
#};

my @two_levels = reachable( $heap, [1], 1 );

say "digraph G {";
dump_node_as_dot( $heap, 'First node', @two_levels );
say "}"

#dump_nodes_with_string($heap, 'onload');
#dump_nodes_with_string($heap, 'bar');
