use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::WorkordersToGroup::AtomicOperation;

{
    package Kernel;
    our $OM;
}

{
    package Local::Handle;
    sub new { bless { AutoCommit => 1, Calls => $_[1] }, $_[0] }
    sub commit {
        push @{ $_[0]->{Calls} }, 'COMMIT';
        $_[0]->{AutoCommit} = 1;
        return 1;
    }
}

{
    package Local::DB;
    sub new {
        my $Self = bless { Calls => [] }, shift;
        $Self->{dbh} = Local::Handle->new( $Self->{Calls} );
        return $Self;
    }
    sub Connect { return 1 }
    sub BeginWork { push @{ $_[0]->{Calls} }, 'BEGIN'; $_[0]->{dbh}->{AutoCommit} = 0; return 1 }
    sub Rollback { push @{ $_[0]->{Calls} }, 'ROLLBACK'; $_[0]->{dbh}->{AutoCommit} = 1; return 1 }
    sub Do { push @{ $_[0]->{Calls} }, $_[2]; return 1 }
}

{
    package Local::Config;
    sub new { bless { Modules => $_[1] }, $_[0] }
    sub Get { return $_[0]->{Modules} if $_[1] eq 'ITSMWorkOrder::EventModule'; return; }
}

{
    package Local::Cache;
    sub Delete { my ( $Self, %Param ) = @_; push @{ $Self->{Deleted} }, $Param{Key}; return 1; }
}

{
    package Local::WorkOrder;
    our @Processed;
    sub new { bless { EventHandlerPipe => undef, DB => $_[1] }, $_[0] }
    sub EventHandlerTransaction {
        my ($Self) = @_;
        die "events ran before commit" if !$Kernel::OM->{DB}->{dbh}->{AutoCommit};
        push @Processed, map { $_->{Event} } @{ $Self->{EventHandlerPipe} || [] };
        $Self->{EventHandlerPipe} = undef;
        return 1;
    }
}

{
    package Local::OM;
    sub new {
        return bless {
            DB => $_[1],
            Config => $_[2],
            WorkOrder => $_[3],
            Cache => $_[4],
        }, $_[0];
    }
    sub Get {
        my ( $Self, $Name ) = @_;
        return $Self->{DB} if $Name eq 'Kernel::System::DB';
        return $Self->{Config} if $Name eq 'Kernel::Config';
        return $Self->{WorkOrder} if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return $Self->{Cache} if $Name eq 'Kernel::System::Cache';
        die "Unexpected dependency $Name";
    }
}

my $DB = Local::DB->new();
my $Atomic = Kernel::System::WorkordersToGroup::AtomicOperation->new( DBObject => $DB );

my ( $OK, $Value, $Error ) = $Atomic->Run( Code => sub { return { ID => 42 }; } );
ok( $OK, 'successful callback commits' );
is( $Value->{ID}, 42, 'callback result is returned' );
is( $DB->{Calls}->[0], 'BEGIN', 'transaction starts' );
is( $DB->{Calls}->[1], 'COMMIT', 'transaction commits through the database handle' );
ok( $DB->{dbh}->{AutoCommit}, 'successful commit restores DBI AutoCommit state' );

($OK, $Value, $Error) = $Atomic->Run( Code => sub { die "EXPECTED_FAILURE\n"; } );
ok( !$OK, 'failed callback does not report success' );
like( $Error, qr/EXPECTED_FAILURE/, 'failure code is preserved' );
is( $DB->{Calls}->[-1], 'ROLLBACK', 'failed callback rolls back' );

$DB->{dbh}->{AutoCommit} = 0;
($OK, $Value, $Error) = $Atomic->Run( Code => sub { return 1; } );
ok( $OK, 'nested operation uses a savepoint' );
is( $DB->{Calls}->[-1], 'RELEASE SAVEPOINT WOTGAtomic', 'nested savepoint is released' );

my $EventModules = { '01-Test' => { Transaction => 0 } };
my $WorkOrder = Local::WorkOrder->new($DB);
my $Cache = bless { Deleted => [] }, 'Local::Cache';
$Kernel::OM = Local::OM->new( $DB, Local::Config->new($EventModules), $WorkOrder, $Cache );
$DB->{dbh}->{AutoCommit} = 1;
($OK, $Value, $Error) = $Atomic->Run(
    NativeWorkOrderEvents => 1,
    Code => sub {
        push @{ $WorkOrder->{EventHandlerPipe} ||= [] }, {
            Event => 'WorkOrderUpdatePost',
            Data => { WorkOrderID => 44, ChangeID => 5, OldWorkOrderData => { ChangeID => 5 } },
        };
        ok( $EventModules->{'01-Test'}->{Transaction}, 'native listeners are deferred while the mutation is open' );
        return 1;
    },
);
ok( $OK, 'native-event mutation commits' );
is_deeply( \@Local::WorkOrder::Processed, ['WorkOrderUpdatePost'], 'native events are processed after database commit' );
is( $EventModules->{'01-Test'}->{Transaction}, 0, 'original native event configuration is restored' );

@Local::WorkOrder::Processed = ();
($OK, $Value, $Error) = $Atomic->Run(
    NativeWorkOrderEvents => 1,
    Code => sub {
        push @{ $WorkOrder->{EventHandlerPipe} ||= [] }, {
            Event => 'WorkOrderUpdatePost',
            Data => { WorkOrderID => 45, ChangeID => 6, OldWorkOrderData => { ChangeID => 6 } },
        };
        die "ROLLBACK_EVENT_TEST\n";
    },
);
ok( !$OK, 'failed native-event mutation rolls back' );
ok( !@Local::WorkOrder::Processed, 'rolled-back native events are discarded' );
ok( !defined $WorkOrder->{EventHandlerPipe}, 'failed event queue entries are removed' );
ok( grep( { $_ eq 'WorkOrderGet::ID::45' } @{ $Cache->{Deleted} } ), 'native Work Order cache is invalidated after rollback' );
is( $EventModules->{'01-Test'}->{Transaction}, 0, 'event configuration is restored after rollback' );

$DB->{dbh}->{AutoCommit} = 0;
my $Ran = 0;
($OK, $Value, $Error) = $Atomic->Run(
    NativeWorkOrderEvents => 1,
    Code => sub { $Ran++; return 1; },
);
ok( !$OK, 'native Work Order mutation fails closed inside a caller-owned transaction' );
is( $Error, 'OUTER_TRANSACTION_ACTIVE', 'nested native update reports a stable transaction error' );
is( $Ran, 0, 'nested native mutation callback is not invoked' );
$DB->{dbh}->{AutoCommit} = 1;

done_testing();
