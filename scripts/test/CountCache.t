use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::WorkordersToGroup::Assignment;

{
    package Kernel;
    our $OM;
}

{
    package Local::DB;
    sub new { bless { Count => 3, Queries => 0 }, $_[0] }
    sub Prepare { $_[0]->{Queries}++; return 1; }
    sub FetchrowArray { return $_[0]->{Count}; }
}

{
    package Local::Cache;
    our %Values;
    our $LastTTL;
    sub Get { my ( $Self, %Param ) = @_; return $Values{ $Param{Key} }; }
    sub Set {
        my ( $Self, %Param ) = @_;
        $Values{ $Param{Key} } = $Param{Value};
        $LastTTL = $Param{TTL};
        return 1;
    }
    sub CleanUp { %Values = (); return 1; }
}

{
    package Local::OM;
    sub Get { return bless {}, 'Local::Cache' if $_[1] eq 'Kernel::System::Cache'; die "Unexpected dependency $_[1]"; }
}

my $DB = Local::DB->new();
$Kernel::OM = bless {}, 'Local::OM';
my $Assignment = Kernel::System::WorkordersToGroup::Assignment->new( DBObject => $DB );

is( $Assignment->CountUnassigned( GroupIDs => [ 5, 6 ], UserID => 7 ), 3, 'first count comes from the database' );
$DB->{Count} = 8;
is( $Assignment->CountUnassigned( GroupIDs => [ 5, 6 ], UserID => 7 ), 3, 'same user and groups reuse the cached count' );
is( $DB->{Queries}, 1, 'the global toolbar avoids repeating the count query during the cache window' );
is( $Local::Cache::LastTTL, 30, 'the cached badge expires after 30 seconds' );

my ($UserSevenKey) = grep { /^User_7_/ } keys %Local::Cache::Values;
$Local::Cache::Values{$UserSevenKey}->{ExpiresAt} = time() - 1;
is( $Assignment->CountUnassigned( GroupIDs => [ 5, 6 ], UserID => 7 ), 8, 'expired in-memory cache entries are not reused' );
is( $DB->{Queries}, 2, 'expired count cache is refreshed from the database' );

$Assignment->_InvalidateCountCache();
is( $Assignment->CountUnassigned( GroupIDs => [ 5, 6 ], UserID => 7 ), 8, 'mutation invalidation refreshes the cached badge' );
is( $DB->{Queries}, 3, 'a refreshed count performs one new database query' );
is( $Assignment->CountUnassigned( GroupIDs => [ 5, 6 ], UserID => 8 ), 8, 'count cache keys are isolated per user' );
is( $DB->{Queries}, 4, 'a different user does not reuse another user cache entry' );

done_testing();
