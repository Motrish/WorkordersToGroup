use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::WorkordersToGroup::Assignment;

{
    package Local::DB;
    sub new { bless { Rows => [], Calls => [] }, $_[0] }
    sub Prepare {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Calls} }, \%Param;
        $Self->{Rows} = [ @{ $Param{TestRows} } ] if exists $Param{TestRows};
        return 1;
    }
    sub FetchrowArray {
        my ($Self) = @_;
        my $Row = shift @{ $Self->{Rows} } || return;
        return @{$Row};
    }
}

my $DB = Local::DB->new();
my $Assignment = Kernel::System::WorkordersToGroup::Assignment->new( DBObject => $DB );

my $NextRows = $Assignment->List(
    GroupIDs => [5],
    Filter => 'all',
    Limit => 50,
    Start => 0,
    CursorChangeTime => '2026-09-20 12:00:00',
    CursorID => 100,
    CursorDirection => 'next',
);
my $NextQuery = $DB->{Calls}->[-1];
like( $NextQuery->{SQL}, qr/a\.change_time < \? OR \(a\.change_time = \? AND a\.id < \?\)/, 'next page uses a bound keyset predicate' );
like( $NextQuery->{SQL}, qr/ORDER BY a\.change_time DESC, a\.id DESC\z/, 'next page preserves descending display order' );
is( $NextQuery->{Start} || 0, 0, 'keyset pagination does not ask OTOBO DB::Prepare to discard prior rows' );

$DB->{Calls} = [];
$DB->{Rows} = [
    [ 51, 150, 8, 5, undef, '', '', 1, '2026-09-20 12:00:01' ],
    [ 52, 151, 8, 5, undef, '', '', 1, '2026-09-20 12:00:02' ],
];
my $PreviousRows = $Assignment->List(
    GroupIDs => [5],
    Filter => 'all',
    Limit => 50,
    CursorChangeTime => '2026-09-20 12:00:00',
    CursorID => 50,
    CursorDirection => 'previous',
);
like( $DB->{Calls}->[-1]->{SQL}, qr/a\.change_time > \? OR \(a\.change_time = \? AND a\.id > \?\)/, 'previous page uses the inverse keyset predicate' );
like( $DB->{Calls}->[-1]->{SQL}, qr/ORDER BY a\.change_time ASC, a\.id ASC\z/, 'previous query walks toward newer rows efficiently' );
is_deeply( [ map { $_->{ID} } @{$PreviousRows} ], [ 52, 51 ], 'previous page is returned in the normal descending display order' );

done_testing();
