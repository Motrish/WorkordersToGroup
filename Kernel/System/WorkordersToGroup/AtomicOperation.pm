# --
# Transaction boundary for WorkordersToGroup mutations.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::System::WorkordersToGroup::AtomicOperation;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::ITSMChange::ITSMWorkOrder',
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = { DBObject => $Param{DBObject} || $Kernel::OM->Get('Kernel::System::DB') };
    return bless $Self, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    return ( 0, undef, 'CALLBACK_INVALID' ) if ref $Param{Code} ne 'CODE';

    my $DBObject = $Self->{DBObject};
    return ( 0, undef, 'DB_CONNECT_FAILED' ) if !$DBObject->Connect();
    my $Handle = $DBObject->{dbh};
    return ( 0, undef, 'DB_HANDLE_UNAVAILABLE' ) if !$Handle;

    my $NativeEvents = $Param{NativeWorkOrderEvents} ? 1 : 0;
    # ITSMWorkOrder emits some side effects immediately and queues others.
    # A savepoint cannot tell us when its caller will commit the outer
    # transaction, so do not perform native Work Order updates in that mode.
    return ( 0, undef, 'OUTER_TRANSACTION_ACTIVE' )
        if $NativeEvents && !$Handle->{AutoCommit};

    my $Mode;
    if ( $Handle->{AutoCommit} ) {
        return ( 0, undef, 'TRANSACTION_BEGIN_FAILED' ) if !$DBObject->BeginWork();
        $Mode = 'TRANSACTION';
    }
    else {
        return ( 0, undef, 'SAVEPOINT_CREATE_FAILED' )
            if !$DBObject->Do( SQL => 'SAVEPOINT WOTGAtomic' );
        $Mode = 'SAVEPOINT';
    }

    my ( $WorkOrderObject, $EventModules, @EventModuleTransactions, @OriginalEvents );
    my $EventCountBefore = 0;
    if ($NativeEvents) {
        $WorkOrderObject = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder');
        $EventModules = $Kernel::OM->Get('Kernel::Config')->Get('ITSMWorkOrder::EventModule');
        if ( ref $EventModules eq 'HASH' ) {
            for my $Key ( keys %{$EventModules} ) {
                my $Config = $EventModules->{$Key};
                next if ref $Config ne 'HASH';
                push @EventModuleTransactions, [ $Config, exists $Config->{Transaction}, $Config->{Transaction} ];
                $Config->{Transaction} = 1;
            }
        }
        @OriginalEvents = $WorkOrderObject->{EventHandlerPipe}
            ? @{ $WorkOrderObject->{EventHandlerPipe} } : ();
        $EventCountBefore = @OriginalEvents;
    }

    my ( $Result, $Error );
    my $Completed = eval {
        $Result = $Param{Code}->();
        die "WOTG_OPERATION_RETURNED_FALSE\n" if !$Result;
        1;
    };
    $Error = $@;

    if ($Completed) {
        my $Committed = $Mode eq 'TRANSACTION'
            ? $Handle->commit()
            : $DBObject->Do( SQL => 'RELEASE SAVEPOINT WOTGAtomic' );
        if ($Committed) {
            $Self->_NativeEventsFinish(
                WorkOrderObject => $WorkOrderObject,
                Transactions   => \@EventModuleTransactions,
                Before         => $EventCountBefore,
                Original       => \@OriginalEvents,
                Commit         => 1,
            ) if $NativeEvents;
            return ( 1, $Result, undef );
        }
        $Error = "WOTG_OPERATION_COMMIT_FAILED\n";
    }

    if ( $Mode eq 'TRANSACTION' ) {
        $DBObject->Rollback();
    }
    else {
        $DBObject->Do( SQL => 'ROLLBACK TO SAVEPOINT WOTGAtomic' );
        $DBObject->Do( SQL => 'RELEASE SAVEPOINT WOTGAtomic' );
    }

    $Self->_NativeEventsFinish(
        WorkOrderObject => $WorkOrderObject,
        Transactions   => \@EventModuleTransactions,
        Before         => $EventCountBefore,
        Original       => \@OriginalEvents,
        Commit         => 0,
    ) if $NativeEvents;

    $Error ||= 'WOTG_OPERATION_FAILED';
    $Error =~ s/\s+\z//;
    return ( 0, undef, $Error );
}

sub _NativeEventsFinish {
    my ( $Self, %Param ) = @_;
    my $WorkOrderObject = $Param{WorkOrderObject};
    return if !$WorkOrderObject;

    my $Pipe = $WorkOrderObject->{EventHandlerPipe} || [];
    my @NewEvents = @{$Pipe} > $Param{Before}
        ? @{$Pipe}[ $Param{Before} .. $#{$Pipe} ]
        : ();

    if ( $Param{Commit} && @NewEvents ) {
        # Run only the events emitted by this operation. Keep earlier queued
        # events intact and deliver the new events only after SQL commit.
        $WorkOrderObject->{EventHandlerPipe} = \@NewEvents;
        my $Processed = eval { $WorkOrderObject->EventHandlerTransaction(); 1; };
        if ( !$Processed ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => 'WorkordersToGroup committed its database changes, but native Work Order events failed: ' . $@,
            );
        }
        $WorkOrderObject->{EventHandlerTransaction} = 0;
    }

    my $Original = $Param{Original} || [];
    $WorkOrderObject->{EventHandlerPipe} = @{$Original} ? [ @{$Original} ] : undef;

    if ( !$Param{Commit} ) {
        my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
        my %Invalidated;
        for my $Event (@NewEvents) {
            next if ref $Event ne 'HASH' || ref $Event->{Data} ne 'HASH';
            my $Data = $Event->{Data};
            my $OldData = ref $Data->{OldWorkOrderData} eq 'HASH' ? $Data->{OldWorkOrderData} : {};
            my $WorkOrderID = $Data->{WorkOrderID} || $OldData->{WorkOrderID};
            next if !$WorkOrderID || $Invalidated{$WorkOrderID}++;
            $CacheObject->Delete(
                Type => 'ITSMChangeManagement',
                Key  => 'WorkOrderGet::ID::' . $WorkOrderID,
            );
            my $ChangeID = $Data->{ChangeID} || $OldData->{ChangeID};
            if ($ChangeID) {
                $CacheObject->Delete( Type => 'ITSMChangeManagement', Key => 'WorkOrderList::ChangeID::' . $ChangeID );
                $CacheObject->Delete( Type => 'ITSMChangeManagement', Key => 'WorkOrderChangeEffortsGet::ChangeID::' . $ChangeID );
                $CacheObject->Delete( Type => 'ITSMChangeManagement', Key => 'WorkOrderChangeTimeGet::ChangeID::' . $ChangeID );
            }
        }
    }

    for my $Entry ( @{ $Param{Transactions} || [] } ) {
        my ( $Config, $HadValue, $Value ) = @{$Entry};
        if ($HadValue) {
            $Config->{Transaction} = $Value;
        }
        else {
            delete $Config->{Transaction};
        }
    }
    return 1;
}

1;
