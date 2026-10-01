# --
# Preview and import group assignments from CustomChangeAutomation 0.3.x.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::System::WorkordersToGroup::Migration;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Group',
    'Kernel::System::ITSMChange::ITSMWorkOrder',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    return bless { DBObject => $Param{DBObject} || $Kernel::OM->Get('Kernel::System::DB') }, $Type;
}

sub Preview {
    my ( $Self, %Param ) = @_;
    return if !$Self->_AdminOrManager( UserID => $Param{UserID} );
    my $Rows = $Self->_SourceRows( Limit => $Param{Limit} ) || return;
    my %Counts = ( Read => 0, Create => 0, Existing => 0, Conflict => 0, Invalid => 0 );
    my @Rows;
    my $AssignmentObject = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my %Assignable = map { $_ => 1 } @{ $AssignmentObject->AssignableGroupIDs() || [] };
    for my $Source ( @{$Rows} ) {
        $Counts{Read}++;
        my $Current = $AssignmentObject->Get( WorkOrderID => $Source->{WorkOrderID} );
        my $Status = 'CREATE';
        if ( !$Assignable{ $Source->{GroupID} } ) {
            $Status = 'GROUP_NOT_ASSIGNABLE';
        }
        elsif ($Current) {
            $Status = $Current->{GroupID} == $Source->{GroupID} ? 'ALREADY_MATCHES' : 'GROUP_CONFLICT';
        }
        else {
            my %Group = $Kernel::OM->Get('Kernel::System::Group')->GroupGet( ID => $Source->{GroupID} );
            my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
                WorkOrderID => $Source->{WorkOrderID}, UserID => $Param{UserID},
            );
            $Status = 'SOURCE_INVALID' if !$Group{ID} || ( $Group{ValidID} || '' ) ne '1' || !$WorkOrder;
        }
        $Counts{Existing}++ if $Status eq 'ALREADY_MATCHES';
        $Counts{Create}++ if $Status eq 'CREATE';
        $Counts{Conflict}++ if $Status eq 'GROUP_CONFLICT';
        $Counts{Invalid}++ if $Status eq 'SOURCE_INVALID' || $Status eq 'GROUP_NOT_ASSIGNABLE';
        push @Rows, { %{$Source}, Status => $Status };
    }
    return { Success => 1, Counts => \%Counts, Rows => \@Rows };
}

sub Apply {
    my ( $Self, %Param ) = @_;
    return if !$Self->_AdminOrManager( UserID => $Param{UserID} );
    my $Preview = $Self->Preview( UserID => $Param{UserID}, Limit => $Param{Limit} ) || return;
    return { Success => 0, Code => 'MIGRATION_HAS_CONFLICTS', Preview => $Preview }
        if $Preview->{Counts}->{Conflict} || $Preview->{Counts}->{Invalid};

    my %Counts = ( Created => 0, Existing => 0, Failed => 0 );
    my @Issues;
    for my $Row ( @{ $Preview->{Rows} } ) {
        next if $Row->{Status} eq 'ALREADY_MATCHES';
        my $Result = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->Assign(
            WorkOrderID   => $Row->{WorkOrderID},
            GroupID       => $Row->{GroupID},
            UserID        => $Param{UserID},
            ChangeID      => $Row->{ChangeID},
            SourcePackage => 'CustomChangeAutomation',
            SourceKey     => "$Row->{InstanceID}:$Row->{Slot}",
        );
        if ( !$Result || !$Result->{Success} ) {
            $Counts{Failed}++;
            push @Issues, { WorkOrderID => $Row->{WorkOrderID}, Status => $Result ? $Result->{Code} : 'UNKNOWN' };
        }
        elsif ( $Result->{Existing} ) {
            $Counts{Existing}++;
        }
        else {
            $Counts{Created}++;
        }
    }
    return { Success => @Issues ? 0 : 1, Counts => \%Counts, Issues => \@Issues };
}

sub _SourceRows {
    my ( $Self, %Param ) = @_;
    my $DBObject = $Self->{DBObject};
    return if !$DBObject->Prepare(
        SQL => 'SELECT s.instance_id, s.slot, s.group_id, s.workorder_id, i.change_id FROM change_auto_inst_slot s LEFT JOIN change_auto_instance i ON i.id = s.instance_id WHERE s.workorder_id IS NOT NULL ORDER BY s.instance_id, s.slot',
        Limit => $Param{Limit},
    );
    my @Rows;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Rows, { InstanceID => $Row[0], Slot => $Row[1], GroupID => $Row[2], WorkOrderID => $Row[3], ChangeID => $Row[4] };
    }
    return \@Rows;
}

sub _AdminOrManager {
    my ( $Self, %Param ) = @_;
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %Granted = $GroupObject->PermissionUserGet( UserID => $Param{UserID}, Type => 'rw' );
    for my $Name (qw(admin itsm-change-manager)) {
        my $ID = $GroupObject->GroupLookup( Group => $Name ) || next;
        return 1 if $Granted{$ID};
    }
    return;
}

1;
