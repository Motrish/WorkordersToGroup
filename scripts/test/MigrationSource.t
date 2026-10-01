use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::WorkordersToGroup::Migration;

{
    package Local::DB;
    sub new { bless { Position => 0 }, $_[0] }
    sub Prepare {
        my ( $Self, %Param ) = @_;
        $Self->{Limit} = $Param{Limit};
        $Self->{Position} = 0;
        return 1;
    }
    sub FetchrowArray {
        my ($Self) = @_;
        return if $Self->{Position} >= 10005;
        my $ID = ++$Self->{Position};
        return ( int( ( $ID - 1 ) / 5 ) + 1, $ID % 5, 6, $ID, 90 );
    }
}

my $DB = Local::DB->new();
my $Migration = Kernel::System::WorkordersToGroup::Migration->new( DBObject => $DB );
my $Rows = $Migration->_SourceRows();
is( scalar @{$Rows}, 10005, 'migration source reads more than 10,000 legacy rows' );
ok( !defined $DB->{Limit}, 'default migration source query has no fixed row limit' );
is( $Rows->[-1]->{WorkOrderID}, 10005, 'the final legacy row remains reachable' );

done_testing();
