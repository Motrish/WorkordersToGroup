# --
# Group ownership and team take API for native ITSM Work Orders.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::System::WorkordersToGroup::Assignment;

use strict;
use warnings;
use utf8;
use JSON::PP qw(encode_json);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Group',
    'Kernel::System::ITSMChange::ITSMWorkOrder',
    'Kernel::System::Cache',
    'Kernel::System::Log',
    'Kernel::System::User',
    'Kernel::System::WorkordersToGroup::AtomicOperation',
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {
        DBObject => $Param{DBObject} || $Kernel::OM->Get('Kernel::System::DB'),
    };
    return bless $Self, $Type;
}

sub Assign {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $GroupID, $UserID ) = @Param{qw(WorkOrderID GroupID UserID)};
    return $Self->_Failure('INPUT_INVALID')
        if !$Self->_ID($WorkOrderID) || !$Self->_ID($GroupID) || !$Self->_ID($UserID);
    return $Self->_Failure('SOURCE_REFERENCE_INVALID')
        if length( $Param{SourcePackage} || '' ) > 100 || length( $Param{SourceKey} || '' ) > 250;

    my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID );
    return $Self->_Failure('WORKORDER_NOT_FOUND') if !$WorkOrder;
    my $Group = $Self->_GroupGet( GroupID => $GroupID );
    return $Self->_Failure('GROUP_NOT_FOUND') if !$Group;
    return $Self->_Failure('GROUP_INACTIVE') if !$Self->_GroupValid($Group);
    return $Self->_Failure('GROUP_NOT_ASSIGNABLE') if !$Self->_GroupAssignable($GroupID);

    my $ChangeID = $Param{ChangeID} || $WorkOrder->{ChangeID} || undef;
    return $Self->_InsertAssignment(
        WorkOrderID    => $WorkOrderID,
        ChangeID       => $ChangeID,
        GroupID        => $GroupID,
        SourcePackage  => $Param{SourcePackage} || '',
        SourceKey      => $Param{SourceKey} || '',
        UserID         => $UserID,
        Event          => 'ASSIGNED',
        Details        => $Param{Details},
    );
}

sub Get {
    my ( $Self, %Param ) = @_;
    return if !$Self->_ID( $Param{WorkOrderID} );
    my $WorkOrderID = $Param{WorkOrderID};
    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT id, workorder_id, change_id, group_id, claimed_agent_id, source_package, source_key, version FROM wotg_assignment WHERE workorder_id = ?',
        Bind => [ \$WorkOrderID ],
    );
    my @Row = $Self->{DBObject}->FetchrowArray();
    return if !@Row;
    return {
        ID             => $Row[0],
        WorkOrderID    => $Row[1],
        ChangeID       => $Row[2],
        GroupID        => $Row[3],
        ClaimedAgentID => $Row[4],
        SourcePackage  => $Row[5] || '',
        SourceKey      => $Row[6] || '',
        Version        => $Row[7],
    };
}

sub List {
    my ( $Self, %Param ) = @_;
    return [] if ref $Param{GroupIDs} ne 'ARRAY' || !@{ $Param{GroupIDs} };
    my @GroupIDs = grep { $Self->_ID($_) } @{ $Param{GroupIDs} };
    return [] if !@GroupIDs;
    my @Bind = map { \$GroupIDs[$_] } 0 .. $#GroupIDs;
    my $SQL;
    if ( $Param{Filter} && $Param{Filter} eq 'unassigned' ) {
        $SQL = 'SELECT a.id, a.workorder_id, a.change_id, a.group_id, a.claimed_agent_id, a.source_package, a.source_key, a.version, a.change_time'
            . ' FROM wotg_assignment a INNER JOIN change_workorder wo ON wo.id = a.workorder_id'
            . ' WHERE a.group_id IN (' . join( ', ', ('?') x @GroupIDs ) . ')'
            . ' AND (a.claimed_agent_id IS NULL OR a.claimed_agent_id = 0)'
            . ' AND (wo.workorder_agent_id IS NULL OR wo.workorder_agent_id = 0)'
            . " AND (wo.workorder_state_id = 0 OR EXISTS (SELECT 1 FROM general_catalog state_gc"
            . " WHERE state_gc.id = wo.workorder_state_id AND state_gc.general_catalog_class = 'ITSM::ChangeManagement::WorkOrder::State'))"
            . " AND NOT EXISTS (SELECT 1 FROM change_state_machine sm INNER JOIN general_catalog gc"
            . " ON gc.id = sm.state_id AND gc.general_catalog_class = 'ITSM::ChangeManagement::WorkOrder::State'"
            . ' WHERE sm.state_id = wo.workorder_state_id AND sm.next_state_id = 0)';
    }
    else {
        $SQL = 'SELECT a.id, a.workorder_id, a.change_id, a.group_id, a.claimed_agent_id, a.source_package, a.source_key, a.version, a.change_time'
            . ' FROM wotg_assignment a INNER JOIN change_workorder wo ON wo.id = a.workorder_id'
            . ' WHERE a.group_id IN (' . join( ', ', ('?') x @GroupIDs ) . ')';
    }
    if ( $Param{Filter} && $Param{Filter} eq 'mine' ) {
        return [] if !$Self->_ID( $Param{UserID} );
        my $UserID = $Param{UserID};
        $SQL .= ' AND a.claimed_agent_id = ?';
        push @Bind, \$UserID;
    }

    my $CursorTime = $Param{CursorChangeTime} || '';
    my $CursorID = $Param{CursorID} || '';
    my $Direction = $Param{CursorDirection} || '';
    my $HasCursor = $CursorTime =~ /\A\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\z/
        && $Self->_ID($CursorID) && $Direction =~ /\A(?:next|previous)\z/;
    if ($HasCursor) {
        my $Operator = $Direction eq 'next' ? '<' : '>';
        $SQL .= " AND (a.change_time $Operator ? OR (a.change_time = ? AND a.id $Operator ?))";
        push @Bind, \$CursorTime, \$CursorTime, \$CursorID;
    }
    $SQL .= $HasCursor && $Direction eq 'previous'
        ? ' ORDER BY a.change_time ASC, a.id ASC'
        : ' ORDER BY a.change_time DESC, a.id DESC';

    my $Limit = $Param{Limit} || 200;
    $Limit = 500 if $Limit > 500;
    my $Start = $HasCursor ? 0 : ( $Param{Start} || 0 );
    $Start = 0 if $Start !~ /\A\d+\z/;
    return [] if !$Self->{DBObject}->Prepare( SQL => $SQL, Bind => \@Bind, Limit => $Limit, Start => $Start );
    my @Items;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        push @Items, {
            ID             => $Row[0],
            WorkOrderID    => $Row[1],
            ChangeID       => $Row[2],
            GroupID        => $Row[3],
            ClaimedAgentID => $Row[4],
            SourcePackage  => $Row[5] || '',
            SourceKey      => $Row[6] || '',
            Version        => $Row[7],
            ChangeTime     => $Row[8],
        };
    }
    @Items = reverse @Items if $HasCursor && $Direction eq 'previous';
    return \@Items;
}

sub CountUnassigned {
    my ( $Self, %Param ) = @_;
    return 0 if ref $Param{GroupIDs} ne 'ARRAY' || !@{ $Param{GroupIDs} };
    my @GroupIDs = grep { $Self->_ID($_) } @{ $Param{GroupIDs} };
    return 0 if !@GroupIDs;
    my $CacheKey;
    if ( $Self->_ID( $Param{UserID} ) ) {
        $CacheKey = 'User_' . $Param{UserID} . '_Groups_' . join( '_', sort { $a <=> $b } @GroupIDs );
        my $Cached;
        eval {
            $Cached = $Kernel::OM->Get('Kernel::System::Cache')->Get(
                Type => 'WorkordersToGroupCount', Key => $CacheKey,
            );
        };
        return $Cached->{Count}
            if ref $Cached eq 'HASH'
            && defined $Cached->{ExpiresAt}
            && $Cached->{ExpiresAt} > time()
            && defined $Cached->{Count}
            && $Cached->{Count} =~ /\A\d+\z/;
    }
    my @Bind = map { \$GroupIDs[$_] } 0 .. $#GroupIDs;
    return 0 if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT COUNT(a.id) FROM wotg_assignment a INNER JOIN change_workorder wo ON wo.id = a.workorder_id'
            . ' WHERE a.group_id IN (' . join( ', ', ('?') x @GroupIDs ) . ')'
            . ' AND (a.claimed_agent_id IS NULL OR a.claimed_agent_id = 0)'
            . ' AND (wo.workorder_agent_id IS NULL OR wo.workorder_agent_id = 0)'
            . " AND (wo.workorder_state_id = 0 OR EXISTS (SELECT 1 FROM general_catalog state_gc"
            . " WHERE state_gc.id = wo.workorder_state_id AND state_gc.general_catalog_class = 'ITSM::ChangeManagement::WorkOrder::State'))"
            . " AND NOT EXISTS (SELECT 1 FROM change_state_machine sm INNER JOIN general_catalog gc"
            . " ON gc.id = sm.state_id AND gc.general_catalog_class = 'ITSM::ChangeManagement::WorkOrder::State'"
            . ' WHERE sm.state_id = wo.workorder_state_id AND sm.next_state_id = 0)',
        Bind => \@Bind,
    );
    my ($Count) = $Self->{DBObject}->FetchrowArray();
    $Count ||= 0;
    if ($CacheKey) {
        eval {
            $Kernel::OM->Get('Kernel::System::Cache')->Set(
                Type  => 'WorkordersToGroupCount',
                Key   => $CacheKey,
                Value => { Count => 0 + $Count, ExpiresAt => time() + 30 },
                TTL   => 30,
            );
        };
    }
    return $Count;
}

sub SetTarget {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $TargetType, $TargetID, $UserID ) = @Param{qw(WorkOrderID TargetType TargetID UserID)};
    return $Self->_Failure('INPUT_INVALID')
        if !$Self->_ID($WorkOrderID) || !$Self->_ID($UserID) || !defined $TargetType || $TargetType !~ /\A(?:user|group|none)\z/;
    return $Self->_Failure('TARGET_ID_INVALID')
        if $TargetType ne 'none' && !$Self->_ID($TargetID);

    my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID )
        || return $Self->_Failure('WORKORDER_NOT_FOUND');
    my $PermissionConfig = $Kernel::OM->Get('Kernel::Config')->Get(
        'ITSMWorkOrder::Frontend::AgentITSMWorkOrderAgent',
    ) || {};
    my $Access = $Kernel::OM->Get('Kernel::System::ITSMChange')->Permission(
        Type        => $PermissionConfig->{Permission} || 'rw',
        Action      => 'AgentITSMWorkOrderAgent',
        ChangeID    => $WorkOrder->{ChangeID},
        WorkOrderID => $WorkOrderID,
        UserID      => $UserID,
    );
    return $Self->_Failure('NATIVE_PERMISSION_REQUIRED') if !$Access;

    my $Target;
    if ( $TargetType eq 'user' ) {
        my %Agent = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $TargetID, Valid => 1 );
        return $Self->_Failure('AGENT_INVALID') if !$Agent{UserID};
    }
    elsif ( $TargetType eq 'group' ) {
        $Target = $Self->_GroupGet( GroupID => $TargetID );
        return $Self->_Failure('GROUP_NOT_FOUND') if !$Target;
        return $Self->_Failure('GROUP_INACTIVE') if !$Self->_GroupValid($Target);
        return $Self->_Failure('GROUP_NOT_ASSIGNABLE') if !$Self->_GroupAssignable($TargetID);
    }

    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        NativeWorkOrderEvents => 1,
        Code => sub {
            $Self->_NativeWorkOrderLock( WorkOrderID => $WorkOrderID )
                || die "WORKORDER_NOT_FOUND\n";
            my $CurrentWorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID )
                || die "WORKORDER_NOT_FOUND\n";
            my $CurrentAccess = $Kernel::OM->Get('Kernel::System::ITSMChange')->Permission(
                Type        => $PermissionConfig->{Permission} || 'rw',
                Action      => 'AgentITSMWorkOrderAgent',
                ChangeID    => $CurrentWorkOrder->{ChangeID},
                WorkOrderID => $WorkOrderID,
                UserID      => $UserID,
            );
            die "NATIVE_PERMISSION_REQUIRED\n" if !$CurrentAccess;
            my $Current = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID );

            if ( $TargetType eq 'group' ) {
                my $GroupID = $TargetID;
                my $CurrentGroup = $Self->_GroupGet( GroupID => $GroupID );
                die "GROUP_NOT_FOUND\n" if !$CurrentGroup;
                die "GROUP_INACTIVE\n" if !$Self->_GroupValid($CurrentGroup);
                die "GROUP_NOT_ASSIGNABLE\n" if !$Self->_GroupAssignable($GroupID);
                if ( $Current && $Current->{GroupID} == $GroupID ) {
                    if ( $Current->{ClaimedAgentID} ) {
                        die "NATIVE_AGENT_MISMATCH\n"
                            if !$CurrentWorkOrder->{WorkOrderAgentID}
                            || $Current->{ClaimedAgentID} != $CurrentWorkOrder->{WorkOrderAgentID};
                        return { Success => 1, Existing => 1, Assignment => $Current };
                    }
                    if ( !$CurrentWorkOrder->{WorkOrderAgentID} ) {
                        return { Success => 1, Existing => 1, Assignment => $Current };
                    }
                }

                my $OldAgentID = $CurrentWorkOrder->{WorkOrderAgentID};
                if ( $CurrentWorkOrder->{WorkOrderAgentID} ) {
                    my $NativeUpdate = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                        WorkOrderID      => $WorkOrderID,
                        WorkOrderAgentID => undef,
                        UserID           => $UserID,
                    );
                    die "NATIVE_RELEASE_FAILED\n" if !$NativeUpdate;
                }

                my $Assignment;
                if ($Current) {
                    my $Changed = $Self->{DBObject}->Do(
                        SQL => 'UPDATE wotg_assignment SET group_id = ?, claimed_agent_id = NULL, version = version + 1, change_time = current_timestamp, change_by = ? WHERE id = ? AND version = ?',
                        Bind => [ \$GroupID, \$UserID, \$Current->{ID}, \$Current->{Version} ],
                    );
                    die "CONCURRENT_CHANGE\n" if !$Changed;
                    $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_NOT_FOUND\n";
                    die "CONCURRENT_CHANGE\n"
                        if $Assignment->{Version} != $Current->{Version} + 1 || $Assignment->{GroupID} != $GroupID;
                    die "AUDIT_FAILED\n" if !$Self->_Audit(
                        AssignmentID => $Current->{ID}, WorkOrderID => $WorkOrderID,
                        Event => 'GROUP_CHANGED', OldGroupID => $Current->{GroupID}, NewGroupID => $GroupID,
                        OldAgentID => $Current->{ClaimedAgentID} || $OldAgentID, ActorID => $UserID,
                    );
                }
                else {
                    my $Inserted = $Self->{DBObject}->Do(
                        SQL => 'INSERT INTO wotg_assignment (workorder_id, change_id, group_id, claimed_agent_id, source_package, source_key, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, NULL, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
                        Bind => [ \$WorkOrderID, \$CurrentWorkOrder->{ChangeID}, \$GroupID,
                            \$Param{SourcePackage}, \$Param{SourceKey}, \$UserID, \$UserID ],
                    );
                    die "ASSIGNMENT_INSERT_FAILED\n" if !$Inserted;
                    $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_READBACK_FAILED\n";
                    die "AUDIT_FAILED\n" if !$Self->_Audit(
                        AssignmentID => $Assignment->{ID}, WorkOrderID => $WorkOrderID,
                        Event => 'ASSIGNED', OldAgentID => $CurrentWorkOrder->{WorkOrderAgentID},
                        NewGroupID => $GroupID, ActorID => $UserID,
                    );
                }
                return { Success => 1, Existing => 0, Assignment => $Assignment };
            }

            if ( $TargetType eq 'user' ) {
                my %CurrentAgent = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                    UserID => $TargetID, Valid => 1,
                );
                die "AGENT_INVALID\n" if !$CurrentAgent{UserID};
            }

            my $NewAgentID = $TargetType eq 'user' ? $TargetID : undef;
            if ( ( $CurrentWorkOrder->{WorkOrderAgentID} || 0 ) != ( $NewAgentID || 0 ) ) {
                my $NativeUpdate = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                    WorkOrderID      => $WorkOrderID,
                    WorkOrderAgentID => $NewAgentID,
                    UserID           => $UserID,
                );
                die "NATIVE_ASSIGNMENT_FAILED\n" if !$NativeUpdate;
            }
            return { Success => 1, Existing => 1 } if !$Current;

            die "AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Current->{ID}, WorkOrderID => $WorkOrderID,
                Event => $TargetType eq 'user' ? 'DIRECT_AGENT_SET' : 'GROUP_ASSIGNMENT_REMOVED',
                OldGroupID => $Current->{GroupID},
                OldAgentID => $Current->{ClaimedAgentID} || $CurrentWorkOrder->{WorkOrderAgentID},
                NewAgentID => $NewAgentID, ActorID => $UserID,
            );
            my $Removed = $Self->{DBObject}->Do(
                SQL => 'DELETE FROM wotg_assignment WHERE id = ? AND version = ?',
                Bind => [ \$Current->{ID}, \$Current->{Version} ],
            );
            die "CONCURRENT_CHANGE\n" if !$Removed || $Self->Get( WorkOrderID => $WorkOrderID );
            return { Success => 1, Existing => 0 };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'TARGET_UPDATE_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub _AssignmentGetForUpdate {
    my ( $Self, %Param ) = @_;
    return if !$Self->_ID( $Param{WorkOrderID} );
    my $WorkOrderID = $Param{WorkOrderID};
    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT id, workorder_id, change_id, group_id, claimed_agent_id, source_package, source_key, version FROM wotg_assignment WHERE workorder_id = ? FOR UPDATE',
        Bind => [ \$WorkOrderID ],
    );
    my @Row = $Self->{DBObject}->FetchrowArray();
    return if !@Row;
    return {
        ID => $Row[0], WorkOrderID => $Row[1], ChangeID => $Row[2], GroupID => $Row[3],
        ClaimedAgentID => $Row[4], SourcePackage => $Row[5] || '', SourceKey => $Row[6] || '', Version => $Row[7],
    };
}

sub CanTake {
    my ( $Self, %Param ) = @_;
    my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $Param{WorkOrderID}, UserID => $Param{UserID} )
        || return;
    return if $WorkOrder->{WorkOrderAgentID};
    my $NextStateIDs = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMStateMachine')->StateTransitionGet(
        StateID => $WorkOrder->{WorkOrderStateID},
        Class   => 'ITSM::ChangeManagement::WorkOrder::State',
    );
    return if !defined $NextStateIDs;
    return if grep { !$_ } @{$NextStateIDs};
    return 1;
}

sub _NativeWorkOrderLock {
    my ( $Self, %Param ) = @_;
    return if !$Self->_ID( $Param{WorkOrderID} );
    my $WorkOrderID = $Param{WorkOrderID};
    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT id FROM change_workorder WHERE id = ? FOR UPDATE',
        Bind => [ \$WorkOrderID ],
    );
    my @Row = $Self->{DBObject}->FetchrowArray();
    return if !@Row;
    $Kernel::OM->Get('Kernel::System::Cache')->Delete(
        Type => 'ITSMChangeManagement', Key => 'WorkOrderGet::ID::' . $WorkOrderID,
    );
    return 1;
}

sub _NativeWorkOrderExists {
    my ( $Self, %Param ) = @_;
    return if !$Self->_ID( $Param{WorkOrderID} );
    my $WorkOrderID = $Param{WorkOrderID};
    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT id FROM change_workorder WHERE id = ?',
        Bind => [ \$WorkOrderID ],
    );
    my @Row = $Self->{DBObject}->FetchrowArray();
    return @Row ? 1 : 0;
}

sub ListAll {
    my ( $Self, %Param ) = @_;
    my $Limit = $Param{Limit} || 500;
    $Limit = 1000 if $Limit > 1000;
    return [] if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT id, workorder_id, change_id, group_id, claimed_agent_id, source_package, source_key, version FROM wotg_assignment ORDER BY change_time DESC, id DESC',
        Limit => $Limit,
    );
    my @Items;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        push @Items, {
            ID             => $Row[0],
            WorkOrderID    => $Row[1],
            ChangeID       => $Row[2],
            GroupID        => $Row[3],
            ClaimedAgentID => $Row[4],
            SourcePackage  => $Row[5] || '',
            SourceKey      => $Row[6] || '',
            Version        => $Row[7],
        };
    }
    return \@Items;
}

sub Claim {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $UserID ) = @Param{qw(WorkOrderID UserID)};
    return $Self->_Failure('INPUT_INVALID') if !$Self->_ID($WorkOrderID) || !$Self->_ID($UserID);
    my $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || return $Self->_Failure('ASSIGNMENT_NOT_FOUND');
    return $Self->_Failure('GROUP_PERMISSION_REQUIRED')
        if !$Self->_HasGroupPermission( UserID => $UserID, GroupID => $Assignment->{GroupID}, Type => 'rw' );
    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $UserID, Valid => 1 );
    return $Self->_Failure('AGENT_INVALID') if !$User{UserID};
    return $Self->_Failure('WORKORDER_NOT_TAKEABLE')
        if !$Self->CanTake( WorkOrderID => $WorkOrderID, UserID => $UserID );

    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        NativeWorkOrderEvents => 1,
        Code => sub {
            my $Current = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_NOT_FOUND\n";
            my $CurrentGroup = $Self->_GroupGet( GroupID => $Current->{GroupID} );
            die "GROUP_INACTIVE\n" if !$Self->_GroupValid($CurrentGroup);
            die "GROUP_PERMISSION_REQUIRED\n"
                if !$Self->_HasGroupPermission( UserID => $UserID, GroupID => $Current->{GroupID}, Type => 'rw' );
            $Self->_NativeWorkOrderLock( WorkOrderID => $WorkOrderID )
                || die "WORKORDER_NOT_FOUND\n";
            die "WORKORDER_NOT_TAKEABLE\n"
                if !$Self->CanTake( WorkOrderID => $WorkOrderID, UserID => $UserID );
            my %CurrentUser = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $UserID, Valid => 1 );
            die "AGENT_INVALID\n" if !$CurrentUser{UserID};
            if ( $Current->{ClaimedAgentID} ) {
                die "ALREADY_CLAIMED\n" if $Current->{ClaimedAgentID} != $UserID;
                my $ExistingWO = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID )
                    || die "WORKORDER_NOT_FOUND\n";
                die "NATIVE_AGENT_MISMATCH\n"
                    if !$ExistingWO->{WorkOrderAgentID} || $ExistingWO->{WorkOrderAgentID} != $UserID;
                return { Success => 1, Existing => 1, Assignment => $Current };
            }

            my $ID = $Current->{ID};
            my $ClaimAgentID = $UserID;
            $Self->{DBObject}->Do(
                SQL => 'UPDATE wotg_assignment SET claimed_agent_id = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE id = ? AND version = ? AND (claimed_agent_id IS NULL OR claimed_agent_id = 0)',
                Bind => [ \$ClaimAgentID, \$UserID, \$ID, \$Current->{Version} ],
            ) || die "CLAIM_UPDATE_FAILED\n";

            # The conditional update serializes competing claims on this row.
            # Always re-read the winner before changing the native Work Order.
            my $AfterUpdate = $Self->Get( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_NOT_FOUND\n";
            die "CONCURRENT_CHANGE\n"
                if !$AfterUpdate->{ClaimedAgentID} || $AfterUpdate->{ClaimedAgentID} != $UserID
                || $AfterUpdate->{Version} != $Current->{Version} + 1;

            my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID )
                || die "WORKORDER_NOT_FOUND\n";
            die "ALREADY_CLAIMED\n" if $WorkOrder->{WorkOrderAgentID} && $WorkOrder->{WorkOrderAgentID} != $UserID;
            my $Updated = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                WorkOrderID      => $WorkOrderID,
                WorkOrderAgentID => $UserID,
                UserID           => $UserID,
            );
            die "NATIVE_ASSIGNMENT_FAILED\n" if !$Updated;
            die "CLAIM_AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Current->{ID}, WorkOrderID => $WorkOrderID,
                Event => 'CLAIMED', NewAgentID => $UserID, ActorID => $UserID,
            );
            return { Success => 1, Existing => 0, Assignment => $AfterUpdate };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'CLAIM_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub ReassignAgent {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $TargetUserID, $ActorID ) = @Param{qw(WorkOrderID TargetUserID UserID)};
    return $Self->_Failure('INPUT_INVALID')
        if !$Self->_ID($WorkOrderID) || !$Self->_ID($TargetUserID) || !$Self->_ID($ActorID);
    return $Self->_Failure('MANAGER_PERMISSION_REQUIRED') if !$Self->_IsManager( UserID => $ActorID );
    my $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || return $Self->_Failure('ASSIGNMENT_NOT_FOUND');
    return $Self->_Failure('TARGET_NOT_GROUP_MEMBER')
        if !$Self->_HasGroupPermission( UserID => $TargetUserID, GroupID => $Assignment->{GroupID}, Type => 'rw' );
    my %Target = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $TargetUserID, Valid => 1 );
    return $Self->_Failure('AGENT_INVALID') if !$Target{UserID};
    return $Self->_SetAgent( Assignment => $Assignment, AgentID => $TargetUserID, ActorID => $ActorID, Event => 'REASSIGNED' );
}

sub Release {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $ActorID ) = @Param{qw(WorkOrderID UserID)};
    return $Self->_Failure('INPUT_INVALID') if !$Self->_ID($WorkOrderID) || !$Self->_ID($ActorID);
    return $Self->_Failure('MANAGER_PERMISSION_REQUIRED') if !$Self->_IsManager( UserID => $ActorID );
    my $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || return $Self->_Failure('ASSIGNMENT_NOT_FOUND');
    return $Self->_SetAgent( Assignment => $Assignment, AgentID => 0, ActorID => $ActorID, Event => 'RELEASED' );
}

sub ChangeGroup {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $GroupID, $ActorID ) = @Param{qw(WorkOrderID GroupID UserID)};
    return $Self->_Failure('INPUT_INVALID') if !$Self->_ID($WorkOrderID) || !$Self->_ID($GroupID) || !$Self->_ID($ActorID);
    return $Self->_Failure('MANAGER_PERMISSION_REQUIRED') if !$Self->_IsManager( UserID => $ActorID );
    my $Group = $Self->_GroupGet( GroupID => $GroupID );
    return $Self->_Failure('GROUP_NOT_FOUND') if !$Group;
    return $Self->_Failure('GROUP_INACTIVE') if !$Self->_GroupValid($Group);
    return $Self->_Failure('GROUP_NOT_ASSIGNABLE') if !$Self->_GroupAssignable($GroupID);
    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        NativeWorkOrderEvents => 1,
        Code => sub {
            my $Assignment = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_NOT_FOUND\n";
            return { Success => 1, Existing => 1, Assignment => $Assignment } if $Assignment->{GroupID} == $GroupID;
            $Self->_NativeWorkOrderLock( WorkOrderID => $WorkOrderID )
                || die "WORKORDER_NOT_FOUND\n";
            my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $ActorID ) || die "WORKORDER_NOT_FOUND\n";
            die "GROUP_NOT_ASSIGNABLE\n" if !$Self->_GroupAssignable($GroupID);
            my $OldGroupID = $Assignment->{GroupID};
            my $OldAgentID = $Assignment->{ClaimedAgentID} || undef;
            my $NativeAgentID = $WorkOrder->{WorkOrderAgentID} || undef;
            my $KeepAgent = $OldAgentID && !$Param{ReleaseAgent}
                && $NativeAgentID && $NativeAgentID == $OldAgentID
                && $Self->_HasGroupPermission( UserID => $OldAgentID, GroupID => $GroupID, Type => 'rw' );
            if ($KeepAgent) {
                my %Agent = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                    UserID => $OldAgentID, Valid => 1,
                );
                $KeepAgent = $Agent{UserID} ? 1 : 0;
            }
            my $NewAgent = $KeepAgent ? $OldAgentID : undef;
            if ( !$KeepAgent && $NativeAgentID ) {
                my $NativeUpdate = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                    WorkOrderID => $WorkOrderID, WorkOrderAgentID => undef, UserID => $ActorID,
                );
                die "NATIVE_RELEASE_FAILED\n" if !$NativeUpdate;
            }
            my $Changed = $Self->{DBObject}->Do(
                SQL => 'UPDATE wotg_assignment SET group_id = ?, claimed_agent_id = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE id = ? AND version = ?',
                Bind => [ \$GroupID, \$NewAgent, \$ActorID, \$Assignment->{ID}, \$Assignment->{Version} ],
            );
            die "CONCURRENT_CHANGE\n" if !$Changed;
            my $UpdatedAssignment = $Self->Get( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_READBACK_FAILED\n";
            die "CONCURRENT_CHANGE\n"
                if $UpdatedAssignment->{Version} != $Assignment->{Version} + 1
                || $UpdatedAssignment->{GroupID} != $GroupID
                || ( $UpdatedAssignment->{ClaimedAgentID} || 0 ) != ( $NewAgent || 0 );
            die "AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Assignment->{ID}, WorkOrderID => $WorkOrderID,
                Event => 'GROUP_CHANGED', OldGroupID => $OldGroupID, NewGroupID => $GroupID,
                OldAgentID => $OldAgentID || $NativeAgentID, NewAgentID => $NewAgent, ActorID => $ActorID,
            );
            return { Success => 1, Existing => 0, Assignment => $UpdatedAssignment };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'GROUP_CHANGE_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub Remove {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $ActorID ) = @Param{qw(WorkOrderID UserID)};
    return $Self->_Failure('INPUT_INVALID') if !$Self->_ID($WorkOrderID) || !$Self->_ID($ActorID);
    return $Self->_Failure('MANAGER_PERMISSION_REQUIRED') if !$Self->_IsManager( UserID => $ActorID );
    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        Code => sub {
            my $Assignment = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID ) || return { Success => 1, Existing => 1 };
            my $NativeExists = $Self->_NativeWorkOrderExists( WorkOrderID => $WorkOrderID );
            die "WORKORDER_CHECK_FAILED\n" if !defined $NativeExists;
            die "RELEASE_REQUIRED\n" if $Assignment->{ClaimedAgentID} && $NativeExists;
            die "AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Assignment->{ID}, WorkOrderID => $WorkOrderID,
                Event => 'GROUP_ASSIGNMENT_REMOVED', OldGroupID => $Assignment->{GroupID}, ActorID => $ActorID,
            );
            my $ID = $Assignment->{ID};
            die "REMOVE_FAILED\n" if !$Self->{DBObject}->Do(
                SQL => 'DELETE FROM wotg_assignment WHERE id = ? AND version = ?',
                Bind => [ \$ID, \$Assignment->{Version} ],
            );
            die "REMOVE_FAILED\n" if $Self->Get( WorkOrderID => $WorkOrderID );
            return { Success => 1, Existing => 0 };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'REMOVE_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub WorkOrderDeleted {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $ActorID ) = @Param{qw(WorkOrderID UserID)};
    return $Self->_Failure('INPUT_INVALID') if !$Self->_ID($WorkOrderID) || !$Self->_ID($ActorID);

    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        Code => sub {
            my $Assignment = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID );
            return { Success => 1, Existing => 1 } if !$Assignment;
            die "DELETE_AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Assignment->{ID}, WorkOrderID => $WorkOrderID,
                Event => 'WORKORDER_DELETED', OldGroupID => $Assignment->{GroupID},
                OldAgentID => $Assignment->{ClaimedAgentID}, ActorID => $ActorID,
            );
            my $ID = $Assignment->{ID};
            die "ASSIGNMENT_DELETE_FAILED\n" if !$Self->{DBObject}->Do(
                SQL => 'DELETE FROM wotg_assignment WHERE id = ? AND version = ?',
                Bind => [ \$ID, \$Assignment->{Version} ],
            );
            die "ASSIGNMENT_DELETE_FAILED\n" if $Self->Get( WorkOrderID => $WorkOrderID );
            return { Success => 1, Existing => 0 };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'ASSIGNMENT_DELETE_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub AuditList {
    my ( $Self, %Param ) = @_;
    return [] if !$Self->_ID( $Param{WorkOrderID} );
    my $WorkOrderID = $Param{WorkOrderID};
    return [] if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT event_type, old_group_id, new_group_id, old_agent_id, new_agent_id, actor_id, details, create_time FROM wotg_audit WHERE workorder_id = ? ORDER BY id DESC',
        Bind => [ \$WorkOrderID ], Limit => $Param{Limit} || 100,
    );
    my @Rows;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        push @Rows, { Event => $Row[0], OldGroupID => $Row[1], NewGroupID => $Row[2], OldAgentID => $Row[3], NewAgentID => $Row[4], ActorID => $Row[5], Details => $Row[6], CreateTime => $Row[7] };
    }
    return \@Rows;
}

sub _InsertAssignment {
    my ( $Self, %Param ) = @_;
    my ( $WorkOrderID, $ChangeID, $GroupID, $SourcePackage, $SourceKey, $UserID ) = @Param{qw(WorkOrderID ChangeID GroupID SourcePackage SourceKey UserID)};
    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        NativeWorkOrderEvents => 1,
        Code => sub {
            my $Existing = $Self->_AssignmentGetForUpdate( WorkOrderID => $WorkOrderID );
            if ($Existing) {
                die "ASSIGNMENT_EXISTS_DIFFERENT_GROUP\n" if $Existing->{GroupID} != $GroupID;
                return { Success => 1, Existing => 1, Assignment => $Existing };
            }
            my $Group = $Self->_GroupGet( GroupID => $GroupID );
            die "GROUP_NOT_FOUND\n" if !$Group;
            die "GROUP_INACTIVE\n" if !$Self->_GroupValid($Group);
            die "GROUP_NOT_ASSIGNABLE\n" if !$Self->_GroupAssignable($GroupID);

            $Self->_NativeWorkOrderLock( WorkOrderID => $WorkOrderID )
                || die "WORKORDER_NOT_FOUND\n";
            my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $WorkOrderID, UserID => $UserID )
                || die "WORKORDER_NOT_FOUND\n";
            $ChangeID = $WorkOrder->{ChangeID} if $WorkOrder->{ChangeID};
            my $NativeAgentID = $WorkOrder->{WorkOrderAgentID};
            my $ValidClaimedAgentID;
            if ( $NativeAgentID && $NativeAgentID =~ /\A\d+\z/
                && $Self->_HasGroupPermission( UserID => $NativeAgentID, GroupID => $GroupID, Type => 'rw' ) ) {
                my %Agent = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
                    UserID => $NativeAgentID, Valid => 1,
                );
                $ValidClaimedAgentID = $NativeAgentID if $Agent{UserID};
            }
            if ( $NativeAgentID && !$ValidClaimedAgentID ) {
                my $Released = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                    WorkOrderID => $WorkOrderID, WorkOrderAgentID => undef, UserID => $UserID,
                );
                die "NATIVE_RELEASE_FAILED\n" if !$Released;
            }
            my $AgentBind = $ValidClaimedAgentID;
            my $Inserted = $Self->{DBObject}->Do(
                SQL => 'INSERT INTO wotg_assignment (workorder_id, change_id, group_id, claimed_agent_id, source_package, source_key, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)',
                Bind => [ \$WorkOrderID, \$ChangeID, \$GroupID, \$AgentBind, \$SourcePackage, \$SourceKey, \$UserID, \$UserID ],
            );
            die "ASSIGNMENT_INSERT_FAILED\n" if !$Inserted;
            my $Assignment = $Self->Get( WorkOrderID => $WorkOrderID ) || die "ASSIGNMENT_READBACK_FAILED\n";
            die "AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Assignment->{ID}, WorkOrderID => $WorkOrderID,
                Event => $Param{Event} || 'ASSIGNED', NewGroupID => $GroupID,
                OldAgentID => $NativeAgentID && !$ValidClaimedAgentID ? $NativeAgentID : undef,
                NewAgentID => $ValidClaimedAgentID, ActorID => $UserID, Details => $Param{Details},
            );
            return { Success => 1, Existing => 0, Assignment => $Assignment };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'ASSIGNMENT_INSERT_FAILED';
    $Error =~ s/\s+\z//;
    my $Existing = $Self->Get( WorkOrderID => $WorkOrderID );
    return { Success => 1, Existing => 1, Assignment => $Existing } if $Existing && $Existing->{GroupID} == $GroupID;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure( $Error, Assignment => $Existing );
}

sub _SetAgent {
    my ( $Self, %Param ) = @_;
    my $Assignment = $Param{Assignment};
    my $AgentID = $Param{AgentID} || 0;
    my $AgentBind = $AgentID ? $AgentID : undef;
    my $ActorID = $Param{ActorID};
    my ( $Success, $Result, $Error ) = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::AtomicOperation')->Run(
        NativeWorkOrderEvents => 1,
        Code => sub {
            my $Current = $Self->_AssignmentGetForUpdate( WorkOrderID => $Assignment->{WorkOrderID} ) || die "ASSIGNMENT_NOT_FOUND\n";
            die "CONCURRENT_CHANGE\n" if $Current->{Version} != $Assignment->{Version};
            $Self->_NativeWorkOrderLock( WorkOrderID => $Current->{WorkOrderID} )
                || die "WORKORDER_NOT_FOUND\n";
            my $WorkOrder = $Self->_WorkOrderGet( WorkOrderID => $Assignment->{WorkOrderID}, UserID => $ActorID )
                || die "WORKORDER_NOT_FOUND\n";
            my $Native = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                WorkOrderID => $Current->{WorkOrderID},
                WorkOrderAgentID => $AgentID ? $AgentID : undef,
                UserID           => $ActorID,
            );
            die "NATIVE_ASSIGNMENT_FAILED\n" if !$Native;
            my $ID = $Current->{ID};
            my $Updated = $Self->{DBObject}->Do(
                SQL => 'UPDATE wotg_assignment SET claimed_agent_id = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE id = ? AND version = ?',
                Bind => [ \$AgentBind, \$ActorID, \$ID, \$Current->{Version} ],
            );
            die "CONCURRENT_CHANGE\n" if !$Updated;
            die "AUDIT_FAILED\n" if !$Self->_Audit(
                AssignmentID => $Current->{ID}, WorkOrderID => $Current->{WorkOrderID},
                Event => $Param{Event}, OldGroupID => $Current->{GroupID}, NewGroupID => $Current->{GroupID},
                OldAgentID => $Current->{ClaimedAgentID}, NewAgentID => $AgentBind, ActorID => $ActorID,
            );
            my $UpdatedAssignment = $Self->Get( WorkOrderID => $Current->{WorkOrderID} ) || die "ASSIGNMENT_READBACK_FAILED\n";
            die "CONCURRENT_CHANGE\n"
                if $UpdatedAssignment->{Version} != $Current->{Version} + 1
                || ( $UpdatedAssignment->{ClaimedAgentID} || 0 ) != $AgentID;
            return { Success => 1, Existing => 0, Assignment => $UpdatedAssignment };
        },
    );
    if ($Success) {
        $Self->_InvalidateCountCache() if !$Result || !$Result->{Existing};
        return $Result;
    }
    $Error ||= 'ASSIGNMENT_UPDATE_FAILED';
    $Error =~ s/\s+\z//;
    $Error =~ s/^WOTG_//;
    return $Self->_Failure($Error);
}

sub _Audit {
    my ( $Self, %Param ) = @_;
    my $Details = defined $Param{Details} ? encode_json( $Param{Details} ) : undef;
    my ( $WorkOrderID, $AssignmentID, $Event, $OldGroup, $NewGroup, $OldAgent, $NewAgent, $ActorID ) = (
        @Param{qw(WorkOrderID AssignmentID Event OldGroupID NewGroupID OldAgentID NewAgentID ActorID)}
    );
    return $Self->{DBObject}->Do(
        SQL => 'INSERT INTO wotg_audit (workorder_id, assignment_id, event_type, old_group_id, new_group_id, old_agent_id, new_agent_id, actor_id, details, create_time, create_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?)',
        Bind => [ \$WorkOrderID, \$AssignmentID, \$Event, \$OldGroup, \$NewGroup, \$OldAgent, \$NewAgent, \$ActorID, \$Details, \$ActorID ],
    );
}

sub _WorkOrderGet {
    my ( $Self, %Param ) = @_;
    return $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
        WorkOrderID => $Param{WorkOrderID}, UserID => $Param{UserID},
    );
}

sub _GroupGet {
    my ( $Self, %Param ) = @_;
    my %Group = $Kernel::OM->Get('Kernel::System::Group')->GroupGet( ID => $Param{GroupID} );
    return \%Group if $Group{ID};
    return;
}

sub _GroupValid {
    my ( $Self, $Group ) = @_;
    return if !$Group || !$Group->{ID};
    return ( $Group->{ValidID} || '' ) eq '1' ? 1 : undef;
}

sub AssignableGroupIDs {
    my ($Self) = @_;
    my $Configured = $Kernel::OM->Get('Kernel::Config')->Get('WorkordersToGroup::AssignableGroups');
    return [] if ref $Configured ne 'ARRAY';
    my %Allowed = map { $_ => 1 } grep { $Self->_ID($_) } @{$Configured};
    my %Valid = $Kernel::OM->Get('Kernel::System::Group')->GroupList( Valid => 1 );
    return [ sort { $a <=> $b } grep { $Allowed{$_} && $Valid{$_} } keys %Valid ];
}

sub _GroupAssignable {
    my ( $Self, $GroupID ) = @_;
    return if !$Self->_ID($GroupID);
    my $Assignable = $Self->AssignableGroupIDs();
    my $Found = scalar grep { $_ == $GroupID } @{$Assignable};
    return $Found ? 1 : undef;
}

sub _InvalidateCountCache {
    my ($Self) = @_;
    eval {
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp( Type => 'WorkordersToGroupCount' );
    };
    return 1;
}

sub _HasGroupPermission {
    my ( $Self, %Param ) = @_;
    my %Groups = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
        UserID => $Param{UserID}, Type => $Param{Type} eq 'ro' ? 'ro' : 'rw',
    );
    return $Groups{ $Param{GroupID} } ? 1 : undef;
}

sub _IsManager {
    my ( $Self, %Param ) = @_;
    return if !$Self->_ID( $Param{UserID} );
    for my $GroupName (qw(itsm-change-manager admin)) {
        my $GroupID = $Kernel::OM->Get('Kernel::System::Group')->GroupLookup( Group => $GroupName ) || next;
        return 1 if $Self->_HasGroupPermission( UserID => $Param{UserID}, GroupID => $GroupID, Type => 'rw' );
    }
    return;
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return defined $Value && !ref $Value && $Value =~ /\A\d+\z/ && $Value > 0 ? 1 : undef;
}

sub _Failure {
    my ( $Self, $Code, %Extra ) = @_;
    return { Success => 0, Code => $Code || 'UNKNOWN', %Extra };
}

1;
