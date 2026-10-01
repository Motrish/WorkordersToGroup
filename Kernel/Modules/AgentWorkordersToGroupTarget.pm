# --
# Group/user selector endpoint for the native ITSM Work Order Agent popup.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::AgentWorkordersToGroupTarget;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Type, %Param ) = @_;
    return bless { %Param }, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Layout  = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $WorkOrderID = $Request->GetParam( Param => 'WorkOrderID' ) || '';

    return $Layout->ErrorScreen(
        Message => $Layout->{LanguageObject}->Translate('No WorkOrderID is given!'),
        Comment => $Layout->{LanguageObject}->Translate('Please contact the administrator.'),
    ) if $WorkOrderID !~ /\A\d+\z/ || !$WorkOrderID;

    my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
        WorkOrderID => $WorkOrderID,
        UserID      => $Self->{UserID},
    );
    return $Layout->ErrorScreen(
        Message => $Layout->{LanguageObject}->Translate('Work Order not found.'),
        Comment => $Layout->{LanguageObject}->Translate('Please contact the administrator.'),
    ) if !$WorkOrder;

    my $Change = $Kernel::OM->Get('Kernel::System::ITSMChange')->ChangeGet(
        ChangeID => $WorkOrder->{ChangeID},
        UserID   => $Self->{UserID},
    );
    return $Layout->ErrorScreen(
        Message => $Layout->{LanguageObject}->Translate('Change not found for this Work Order.'),
        Comment => $Layout->{LanguageObject}->Translate('Please contact the administrator.'),
    ) if !$Change;

    my $Config = $Kernel::OM->Get('Kernel::Config')->Get(
        'ITSMWorkOrder::Frontend::AgentITSMWorkOrderAgent',
    ) || {};
    my $Allowed = $Kernel::OM->Get('Kernel::System::ITSMChange')->Permission(
        Type        => $Config->{Permission} || 'rw',
        Action      => 'AgentITSMWorkOrderAgent',
        ChangeID    => $WorkOrder->{ChangeID},
        WorkOrderID => $WorkOrderID,
        UserID      => $Self->{UserID},
    );
    return $Layout->NoPermission(
        Message    => $Layout->{LanguageObject}->Translate('You need %s permissions on the change!', $Config->{Permission} || 'rw'),
        WithHeader => 'yes',
    ) if !$Allowed;

    my $Subaction = $Request->GetParam( Param => 'Subaction' ) || '';
    if ( $Subaction eq 'Options' ) {
        return $Self->_Options( WorkOrderID => $WorkOrderID, WorkOrder => $WorkOrder );
    }
    if ( $Subaction eq 'Save' ) {
        $Layout->ChallengeTokenCheck();
        my $Target = $Request->GetParam( Param => 'Target' ) || '';
        my ( $TargetType, $TargetID );
        if ( $Target eq 'none' ) {
            $TargetType = 'none';
        }
        elsif ( $Target =~ /\A(user|group):(\d+)\z/ ) {
            ( $TargetType, $TargetID ) = ( $1, $2 );
        }
        else {
            return $Layout->ErrorScreen(
                Message => $Layout->{LanguageObject}->Translate('Select a valid agent or group.'),
                Comment => $Layout->{LanguageObject}->Translate('The Work Order was not changed.'),
            );
        }

        my $Result = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->SetTarget(
            WorkOrderID => $WorkOrderID,
            TargetType  => $TargetType,
            TargetID    => $TargetID,
            UserID      => $Self->{UserID},
            SourcePackage => 'AgentITSMWorkOrderAgent',
        );
        if ( ref $Result eq 'HASH' && $Result->{Success} ) {
            return $Layout->PopupClose(
                URL => $Self->{Session}{LastWorkOrderView}
                    || "Action=AgentITSMWorkOrderZoom;WorkOrderID=$WorkOrderID",
            );
        }

        my $Code = ref $Result eq 'HASH' && $Result->{Code} ? $Result->{Code} : 'TARGET_UPDATE_FAILED';
        my %ErrorText = (
            AGENT_INVALID                => 'The selected agent is no longer active.',
            GROUP_NOT_FOUND              => 'The selected group no longer exists.',
            GROUP_INACTIVE               => 'The selected group is no longer active.',
            GROUP_NOT_ASSIGNABLE         => 'The selected group is not enabled for Work Order assignment.',
            NATIVE_PERMISSION_REQUIRED   => 'You no longer have permission to assign this Work Order.',
            NATIVE_AGENT_MISMATCH        => 'The saved agent and group assignment no longer match. Choose a new target and save again.',
            WORKORDER_NOT_FOUND          => 'The Work Order no longer exists or is no longer available.',
            NATIVE_RELEASE_FAILED        => 'The current agent could not be released. The assignment was not changed.',
            NATIVE_ASSIGNMENT_FAILED     => 'The Work Order agent could not be updated. The assignment was not changed.',
            ASSIGNMENT_INSERT_FAILED     => 'The group assignment could not be saved. The assignment was not changed.',
            CONCURRENT_CHANGE            => 'The assignment changed while you were editing it. Reload the Work Order and try again.',
        );
        my $Message = $ErrorText{$Code} || 'The Work Order target could not be saved. The assignment was not changed.';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'notice',
            Message  => "WorkordersToGroup target update rejected for WorkOrderID $WorkOrderID by UserID $Self->{UserID}: $Code",
        );
        return $Layout->ErrorScreen(
            Message => $Layout->{LanguageObject}->Translate($Message),
            Comment => $Layout->{LanguageObject}->Translate('The Work Order was not changed.'),
        );
    }

    return $Layout->ErrorScreen(
        Message => $Layout->{LanguageObject}->Translate('Unsupported request.'),
        Comment => $Layout->{LanguageObject}->Translate('Please contact the administrator.'),
    );
}

sub _Options {
    my ( $Self, %Param ) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    # The assignment dropdown must contain every active agent. Out-of-office
    # status affects availability, not whether an agent can own a Work Order.
    my %Users = $UserObject->UserList( Type => 'Long', Valid => 1 );
    my %AllGroups = $GroupObject->GroupList( Valid => 1 );
    my $AssignableGroupIDs = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->AssignableGroupIDs();
    my %Groups = map { $_ => $AllGroups{$_} } grep { exists $AllGroups{$_} } @{$AssignableGroupIDs};

    my @UserOptions = map { { ID => 0 + $_, Name => $Users{$_} } }
        sort { lc( $Users{$a} ) cmp lc( $Users{$b} ) || $a <=> $b } keys %Users;
    my @GroupOptions = map { { ID => 0 + $_, Name => $Groups{$_} } }
        sort { lc( $Groups{$a} ) cmp lc( $Groups{$b} ) || $a <=> $b } keys %Groups;

    my $Assignment = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->Get(
        WorkOrderID => $Param{WorkOrderID},
    );
    my $CurrentTarget = $Assignment
        ? 'group:' . $Assignment->{GroupID}
        : $Param{WorkOrder}->{WorkOrderAgentID}
            ? 'user:' . $Param{WorkOrder}->{WorkOrderAgentID}
            : 'none';

    my $Data = {
        Success       => 1,
        CurrentTarget => $CurrentTarget,
        ChallengeToken => $Layout->{UserChallengeToken},
        NoneLabel     => $Layout->{LanguageObject}->Translate('Unassigned'),
        UsersLabel    => $Layout->{LanguageObject}->Translate('Agents'),
        GroupsLabel   => $Layout->{LanguageObject}->Translate('Groups'),
        LoadingLabel  => $Layout->{LanguageObject}->Translate('The agent and group list is still loading.'),
        ListErrorLabel => $Layout->{LanguageObject}->Translate('The agent and group list could not be loaded.'),
        InvalidCurrentLabel => $Layout->{LanguageObject}->Translate('The current assignment is inactive or no longer available.'),
        InvalidTargetLabel => $Layout->{LanguageObject}->Translate('Select a valid agent or group.'),
        NoAssignableGroupsLabel => $Layout->{LanguageObject}->Translate('No groups are enabled for Work Order assignment. Configure WorkordersToGroup::AssignableGroups in SysConfig.'),
        UserOptions   => \@UserOptions,
        GroupOptions  => \@GroupOptions,
    };
    my $JSON = $Layout->JSONEncode( Data => $Data );
    return $Layout->Attachment(
        ContentType => 'application/json; charset=' . $Layout->{Charset},
        Content     => $JSON,
        Type        => 'inline',
        NoCache     => 1,
    );
}

1;
