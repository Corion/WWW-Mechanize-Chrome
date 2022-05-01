#!perl
use strict;
use warnings;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'say';
use File::Temp 'tempdir';
use Carp 'croak';

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

sub edge( $heap, $idx ) {
    my @vals = edge_at_index( $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{edge_fields}, \@vals
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
        map {
            $_ => get_node_field( $heap, $idx, $_ )
        } @{ $heap->{snapshot}->{meta}->{node_fields} }
    }
}

sub get_node_field($heap, $idx, $fieldname) {
    croak "Invalid node field name '$fieldname'"
        unless exists $node_field_index{ $fieldname };

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $node_field_index{ $fieldname };
    my $val = $heap->{nodes}->[$idx*$node_size+$fi];

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

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $edge_field_index{ $fieldname };
    my $val = $heap->{edges}->[$idx*$edge_size+$fi];

    my $ft = $heap->{snapshot}->{meta}->{edge_types}->[$fi];
    if( ref $ft eq 'ARRAY' ) {
        $val = $ft->[$val]
    } elsif( $ft eq 'number' ) {
        # we use the value as-is
    } elsif( $ft eq 'node' ) {
        # we use the value as-is
    } elsif( $ft eq 'string' ) {
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

sub edges_referencing_node( $heap, $node_id ) {
    my $to_node = $node_field_index{'to_node'};
    filter_edges( $heap, sub($edges, $idx) {
        my $v = get_edge_field( $heap, $idx, 'to_node' );
        if( ! defined $v ) {
            croak "Invalid edge index $idx!";
        };
        $v == $node_id
    })
}

sub edge_ids_from_node( $heap, $node_id ) {
    # Find where our node_id starts in the list of edges. For that, we need
    # to sum the edgecount of all previous nodes.
    # This should maybe later be cached/indexed so we don't always have
    # to rescan the whole array
    my $to_node = $node_field_index{'to_node'};
    filter_edges( $heap, sub($edges, $idx) {
        my $v = get_edge_field( $heap, $idx, 'to_node' );
        if( ! defined $v ) {
            croak "Invalid edge index $idx!";
        };
        $v == $node_id
    })
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

use Data::Dumper;
#my @usage = find_string_exact($heap,'Rick Astley');
my @usage = find_string_exact($heap,'structname');
$usage[0]->{path} =~ /\[(\d+)\]/
    or die "Weirdo path: '$usage[0]->{path}'";
my $idx = $1;
say "'structname' has string id $idx ($usage[0]->{path})";
my @nodes = nodes_with_string_id( $heap, $idx );
say "Nodes referencing that string: " . Dumper \@nodes;
say "Edges referencing that node: " . Dumper [edges_referencing_node( $heap, $nodes[0] )];

# strings <- edge
# strings <- node


#find_value($heap,'Astley');
#find_value($heap,'dQw4w9WgXcQ');

sub dump_nodes( $heap, $string ) {
    @usage = find_string_exact($heap,$string);
    $usage[0]->{path} =~ /\[(\d+)\]/
        or die "Weirdo path: '$usage[0]->{path}'";
    $idx = $1;
    print "Nodes using '$string' " . Dumper [map{full_node($heap,$_)} nodes_with_string_id($heap, $idx)];
}

dump_nodes($heap, 'onload');
dump_nodes($heap, 'bar');
