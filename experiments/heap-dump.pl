#!perl
use 5.020;
use feature 'signatures';
no warnings 'experimental::signatures';
use feature 'say';
use File::Temp 'tempdir', 'tempfile';
use Carp 'croak';

use Data::Dumper;
use WWW::Mechanize::Chrome;
use JSON;
use Log::Log4perl ':easy';
use List::Util 'mesh';
Log::Log4perl->easy_init($WARN);

# We use an in-memory SQLite database as our memory structure to
# better be able to query the graph
use DBI;
use DBD::SQLite;
use DBD::SQLite::VirtualTable::PerlData;
use DBIx::RunSQL;

use Chrome::Heapdump;

my $heapdump;
if( 0 ) {
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

    #my $heapdump = $done->get;
    #open my $fh, '>:raw', 'tmp.heapsnapshot'
    #    or die "$!";
    #print {$fh} $heapdump;
    #close $fh;
} else {
    open my $fh, '<:raw', 'tmp.heapsnapshot'
        or die "$!";
    $heapdump = do { local $/; <$fh> };
}

my $heap = Chrome::Heapdump->from_string($heapdump);

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

my $dbh = $heap->dbh;

# turn into view, node_edges
my $sth= $dbh->prepare( <<'SQL' );
    select
        *
    from node n
    join edge e on e._idx between n.edge_offset and n.edge_offset+n.edge_count-1
    where n.id = ?;
SQL
$sth->execute(1);

# turn into view, node_children
$sth= $dbh->prepare( <<'SQL' );
    select
        *
    from node parent
    join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
    join node child on child._idx = e._to_node_idx
    where parent.id = ?;
SQL
$sth->execute(1);
say "-- children of 1";
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
$sth= $dbh->prepare( <<'SQL' );
    with immediate_children as (
        select
            parent.id as parent_id
          , parent._idx as parent_idx
          , parent.type as parent_type
          , parent.name as parent_name
          , e.name_or_index as relation
          , child.id as child_id
          , child._idx as child_idx
          , child.type as child_type
          , child.name as child_name
        from node parent
        join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
        join node child on child._idx = e._to_node_idx
    )
    select
         *
      from immediate_children
    where parent_id = ?;
SQL
$sth->execute(1);
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
$sth= $dbh->prepare( <<'SQL' );
    with immediate_parents as (
        select
            parent.id as parent_id
          , parent._idx as parent_idx
          , parent.type as parent_type
          , parent.name as parent_name
          , e.name_or_index as relation
          , child.id as child_id
          , child._idx as child_idx
          , child.type as child_type
          , child.name as child_name
        from node child
        join edge e on child._idx = e._to_node_idx
        join node parent on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
    )
    select
         *
      from immediate_parents
    where child_name = ?
      and parent_type = 'object'
SQL
#$sth->execute('bar');
#$sth->execute('Hello World');
$sth->execute('complex_struct');
my $res = $sth->fetchall_arrayref( {});
my $obj = 0+$res->[0]->{parent_id};
say "Target object id: <$obj>";
$sth->execute('complex_struct');
say "-- All JS objects containing a string 'complex_struct'";
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
say "--- Found object $obj";
$sth= $dbh->prepare( <<'SQL' );
    select
           *
      from node
     where id = ?+0
SQL
$sth->execute(0+$obj);
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
say "--- All object properties";
$sth= $dbh->prepare( <<'SQL' );
    with object as (
        select
            parent.id as parent_id
          , parent._idx as parent_idx
          , parent.type as parent_type
          , parent.name as parent_name
          , e.name_or_index as relation
          , child.id as child_id
          , child._idx as child_idx
          , child.type as child_type
          , child.name as child_name
        from node parent
        left join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
        left join node child on e._to_node_idx = child._idx
       where parent.type = 'object'
         and child.type not in ('hidden')
    )
    select
           parent_name
         , parent_id as id
         , parent_idx
         , child_id
         , relation
         , child_type
         , child_name
      from object
    where id = ? +0
    -- group by name, id, _idx
SQL
$sth->execute($obj);
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
say "--- How an array looks";
# Note that the relation is the value for smi numbers (?)
$obj = $dbh->selectall_arrayref(<<'SQL', {}, $obj)->[0]->[0];
    select child.id
      from node parent
      left join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
      left join node child on e._to_node_idx = child._idx
     where parent.id = 0+?
       and e.name_or_index = 'items'
SQL

say "(array 'items': $obj)";

$sth= $dbh->prepare( <<'SQL' );
    with object as (
        select
            parent.id as parent_id
          , parent._idx as parent_idx
          , parent.type as parent_type
          , parent.name as parent_name
          , e.name_or_index as relation
          , child.id as child_id
          , child._idx as child_idx
          , child.type as child_type
          , child.name as child_name
          , case when child.type = 'number' then e.name_or_index
                 when child.type = 'string' then child.name
                else 'Unknown type "' || child.type || '"'
            end as child_value
        from node parent
        left join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
        left join node child on e._to_node_idx = child._idx
    )
    select
           parent_name
         , parent_id as id
         , parent_idx
         , child_id
         , relation
         , child_type
         , child_name
         , child_value
      from object
    where id = ? +0
    order by relation, child_id
    -- group by name, id, _idx
SQL
$sth->execute($obj);
say DBIx::RunSQL->format_results( sth => $sth );

# turn into view, node_children / child_nodes
# Actually, this isn't correct - "smi number" should not be a relation but a value
say "-- Reconstructed JSON object";
$sth= $dbh->prepare( <<'SQL' );
    with object as (
        select
            parent.id as id
          , parent._idx
          , parent.type
          , parent.name
          , e.name_or_index as fieldname
          , child.id   as child_id
          , child._idx as child_idx
          , child.type as child_type
          , child.name as child_name
        from node parent
        join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
        join node child on e._to_node_idx = child._idx
       where parent.type = 'object'
         and child.type not in ('hidden')
    )
    select
           name
         , id
         , _idx
         -- nice try, but that won't hold up when trying to recursively fetch
         -- related object
         -- unless we do a recursive CTE, that is
         , json_group_object(fieldname, child_name)
      from object
    where id = ? +0
    group by name, id, _idx
SQL
$sth->execute($obj);
say DBIx::RunSQL->format_results( sth => $sth );

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

sub filter_edges( $heap, $cb ) {
    my $edges = $heap->edges;
    grep { $cb->($edges, $_) } 0..$heap->{snapshot}->{edge_count}-1
}

# "Parent" nodes?
# Returns edge indices
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

# Find all parent nodes referencing this node
sub parents_idx( $heap, $node_idx ) {
    croak "Invalid node index $node_idx"
        if $node_idx >= $heap->{snapshot}->{node_count};
    say "Edges referencing $node_idx";
    my @edges_idx = edges_referencing_node( $heap, $node_idx );
    say "Nodes having edges @edges_idx";
    my @parents = map { nodes_having_edge( $heap, $_ ) } @edges_idx;
    say "Found @parents";
    return @parents;
}

sub filter_nodes( $heap, $cb ) {
    my $nodes = $heap->{nodes};
    grep { $cb->($nodes, $_) } 0..$heap->{snapshot}->{node_count}-1
}

# Returns indices, not node ids ...
sub nodes_having_edge( $heap, $edge_idx ) {
    filter_nodes( $heap, sub( $nodes, $node_idx ) {
        if( grep {
                $_ == $edge_idx
            } edge_ids_from_node( $heap, $node_idx )) {
            1
        };
    });
}

sub edge_ids_from_node( $heap, $node_idx ) {
    # Find where our node_id starts in the list of edges. For that, we need
    # to sum the edgecount of all previous nodes.
    # This should maybe later be cached/indexed so we don't always have
    # to rescan the whole array

    # This should maybe be done at start
    state @edge_offset = 0;

    if( $#edge_offset < $node_idx ) {
        my $edge_offset = @edge_offset ? $edge_offset[ $#edge_offset ] : 0;
        #use Data::Dumper; warn Dumper \@edge_offset;
        #say "Starting from $edge_offset for $node_idx";

        for my $idx ($#edge_offset..$node_idx-1) {
            #say "(build) Fetching index $idx";
            #$edge_offset += get_node_field($heap,$idx,'edge_count');
            $edge_offset += $heap->get_edge_count($idx);
            $edge_offset[ $idx ] = $edge_offset;
            #say "Building offset $node_idx from $#edge_offset";
        };
        $edge_offset[ $node_idx ] = $edge_offset;

        #my $edge_offset_slow = 0;
        #for my $idx (0..$node_idx-1) {
        #    say "(check) Fetching index $idx";
        #    $edge_offset_slow += get_node_field($heap,$idx,'edge_count');
        #};
        #die "Inconsistent build for $node_idx: $edge_offset_slow != $edge_offset[ $node_idx ]"
        #    if $edge_offset_slow != $edge_offset[ $node_idx ];
    }
    my $edge_offset = $edge_offset[ $node_idx ];
    #my $edges = get_node_field($heap,$node_idx,'edge_count');
    my $edges = $heap->get_edge_count($node_idx);
    croak "Weird edge count for node index $node_idx"
        unless defined $edges;
    croak "Too large edge count for node index $node_idx"
        if $edges+$edge_offset > $heap->edges->@*;

    # XXX are these indices or ids?!
    # our subroutine name says ids
    return @{ $heap->edges }[$edge_offset..$edge_offset+$edges]
}

# "Child" nodes?
# idx -> full nodes
sub nodes_from_node( $heap, $node_idx ) {
    my @edges = edge_ids_from_node( $heap, $node_idx );
    my @node_idxs = map {
        $heap->get_edge_target( $_ );
    } @edges;
    return map { $heap->full_node( $_ ) } @node_idxs
}

sub nodes_with_string_id($heap,$string_id) {
    my $n = $heap->{nodes};
    my $str = $heap->{strings}->[$string_id];
    #croak "No node field index 'name' found"
    #    unless exists $node_field_index{'name'};
    #my $fi = $node_field_index{'name'};
    grep {
        $heap->get_node_field( $_, 'name') eq $str
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
    my @nodes = map { $heap->full_node($_) }
                map { $heap->node_by_id( $_ ) } @node_ids;
    for my $n (@nodes) {
        my @edge_ids = edge_ids_from_node( $heap, $n->{_idx} );
        $n->{edges} = [map { $heap->full_edge($_)} @edge_ids ];
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
    my $node_idx = $edge->{to_node} / $heap->node_size;
    my $targ = $heap->get_node_field( $node_idx, 'id' );

    my $label = $edge->{name_or_index};
    if( $label =~ /^\d+$/ ) {
        $label = '';
    } else {
        $label = qq([label="$label"]);
    };

    return qq{$nid -> $targ$label};
}

sub dump_node_as_dot( $heap, $msg, @node_ids ) {
    use Data::Dumper;
    warn Dumper \@node_ids
        if grep { ! defined $_ } @node_ids;
    my @nodes = map { $heap->full_node($_) }
                map { $heap->node_by_id( $_ ) }
                @node_ids;
    for my $n (@nodes) {
        my @edge_ids = edge_ids_from_node( $heap, $n->{_idx} );
        $n->{edges} = [map {$heap->full_edge($_)} @edge_ids ];
    };

    my %leaves;

    my %node_seen;
    for my $n (@nodes) {
        my $nid = $n->{id};
        next if $node_seen{ $nid }++;
        delete $leaves{ $nid };

        say _node_as_dot( $n );

        for my $e (@{$n->{edges}}) {
            my $node_idx = $e->{to_node}/$heap->node_size;
            my $id = $heap->get_node_field( $node_idx, 'id');
            $leaves{ $id } = 1;
            say _edge_as_dot($n->{id}, $e);
        };
    };
    for my $nid (sort { $a <=> $b } keys %leaves) {
        my $n = $heap->full_node( $heap->node_by_id( $nid ));
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
            my $idx = $heap->node_by_id( $nid );
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

#say "digraph G {";
#say "rankdir = LR";
#dump_node_as_dot( $heap, 'First node', @two_levels );
#say "}"

#dump_nodes_with_string($heap, 'onload');
#dump_nodes_with_string($heap, 'bar');

=head2 C<< node_ancestor_paths $heap, $prefix, $seen >>

  my @paths = node_ancestor_paths( $heap, [$index] );

Finds all the paths from the given set of nodes to the
root node. Returns the paths as indices (?!)

=cut

sub node_ancestor_paths($heap, $prefix, $seen={}) {
    my @res = @$prefix;
    #say "Finding parents of $res[0]";
    my @ancestors;# = parents_idx( $heap, $res[0] );
    #say "ancestors: @ancestors";
    my $dbh = $heap->dbh;

    # turn into view, node_parents
    # Maybe just do a recursive CTE here instead?!
    my $sth= $dbh->prepare( <<'SQL' );
        select
            *
        from node parent
        join edge e on e._idx between parent.edge_offset and parent.edge_offset+parent.edge_count-1
        join node child on child._idx = e._to_node_idx
        where child._idx = 0+?;
SQL
    $sth->execute($res[0]);
    say "-- parents of $res[0] (index)";
    say DBIx::RunSQL->format_results( sth => $sth );
    $sth->execute(0+$res[0]);
    @ancestors = map { $_->{id} } $sth->fetchall_arrayref({})->@*;

    if( @ancestors ) {
        return map {
            node_ancestor_paths( $heap, [$_, @res], $seen )
        }
        grep { ! $seen->{$_}++ } @ancestors;
    } else {
        return $prefix
    }
}

my $str = 'bar';
my $string = [$heap->find_string_exact($str)]->[0]->{index};
die "Could not find the exact string '$str' in the heap"
    unless defined $string;
say "Finding ancestors of $str (index $string)";
my @path = node_ancestor_paths($heap, [$string]);
say "digraph G {";
say "rankdir = LR";
for (@path) {
    dump_node_as_dot( $heap, 'First node', @$_ );
} @path;
say "}";

# Output the path between two nodes
# The approach is to choose the parents of each node until
# we find a common node, which obviously must be a link
# this maybe even is the shortest link
sub node_path( $heap, $start_node, $end_node, $parents_s = {}, $parents_e = {} ) {
    $parents_s->{ $start_node->{id}} = $start_node;
    $parents_e->{ $end_node->{id}} = $end_node;

    if( my @common = (grep { exists $parents_s->{ $_->{id} } } values( %$parents_e ),
                      grep { exists $parents_e->{ $_->{id} } } values( %$parents_s )
                     )) {
        # we found that a common ancestor exists, but we don't know
        # the path :-/
        return @common
    } else {
        # flood-fill by using all parents
        my @p = parents_idx( $heap, $start_node );
        my @q = parents_idx( $heap, $end_node );
    }
}
