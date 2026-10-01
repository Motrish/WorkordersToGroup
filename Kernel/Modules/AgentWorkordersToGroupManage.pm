# --
# Claim or assign a group Work Order from its zoom action menu.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::AgentWorkordersToGroupManage;

use strict;
use warnings;

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

    my $AssignmentObject = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my $Assignment = $AssignmentObject->Get( WorkOrderID => $WorkOrderID );
    my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
        WorkOrderID => $WorkOrderID, UserID => $Self->{UserID},
    );
    return $Layout->ErrorScreen(
        Message => $Layout->{LanguageObject}->Translate('Work Order not found.'),
        Comment => $Layout->{LanguageObject}->Translate('Please contact the administrator.'),
    ) if !$Assignment || !$WorkOrder;

    my $HasViewPermission = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->Permission(
        Type        => 'ro',
        Action      => 'AgentITSMWorkOrderZoom',
        WorkOrderID => $WorkOrderID,
        UserID      => $Self->{UserID},
        LogNo       => 1,
    );
    return $Layout->NoPermission(
        Message    => $Layout->{LanguageObject}->Translate('You need %s permissions on the change!', 'ro'),
        WithHeader => 'yes',
    ) if !$HasViewPermission;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $IsManager = $Self->_IsManager();
    my %RWGroups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
    my $CanClaim = $RWGroups{ $Assignment->{GroupID} }
        && !$Assignment->{ClaimedAgentID}
        && $AssignmentObject->CanTake( WorkOrderID => $WorkOrderID, UserID => $Self->{UserID} ) ? 1 : 0;

    if ( ( $Request->GetParam( Param => 'Subaction' ) || '' ) eq 'Assign' ) {
        return $Layout->NoPermission(
            Message    => $Layout->{LanguageObject}->Translate('You no longer have permission to assign this Work Order.'),
            WithHeader => 'yes',
        ) if !$IsManager;

        $Layout->ChallengeTokenCheck();
        my $TargetUserID = $Request->GetParam( Param => 'TargetUserID' ) || '';
        return $Layout->ErrorScreen(
            Message => $Layout->{LanguageObject}->Translate('Select a valid agent or group.'),
            Comment => $Layout->{LanguageObject}->Translate('The Work Order was not changed.'),
        ) if $TargetUserID !~ /\A\d+\z/ || !$TargetUserID;

        my $Result = $AssignmentObject->ReassignAgent(
            WorkOrderID  => $WorkOrderID,
            TargetUserID => $TargetUserID,
            UserID       => $Self->{UserID},
        );
        if ( ref $Result eq 'HASH' && $Result->{Success} ) {
            return $Layout->PopupClose(
                URL => $Self->{Session}{LastWorkOrderView}
                    || "Action=AgentITSMWorkOrderZoom;WorkOrderID=$WorkOrderID",
            );
        }
        my $Code = ref $Result eq 'HASH' && $Result->{Code} ? $Result->{Code} : 'REASSIGN_FAILED';
        return $Layout->ErrorScreen(
            Message => $Layout->{LanguageObject}->Translate('Assignment was rejected: %s', $Code),
            Comment => $Layout->{LanguageObject}->Translate('The Work Order was not changed.'),
        );
    }

    my @Members;
    if ($IsManager) {
        my %GroupMembers = $GroupObject->PermissionGroupGet(
            GroupID => $Assignment->{GroupID}, Type => 'rw',
        );
        my $UserObject = $Kernel::OM->Get('Kernel::System::User');
        for my $UserID ( sort { $a <=> $b } keys %GroupMembers ) {
            my %User = $UserObject->GetUserData( UserID => $UserID, Valid => 1 );
            next if !$User{UserID};
            my $Name = join ' ', grep { $_ } @User{qw(UserFirstname UserLastname)};
            $Name ||= $User{UserFullname} || $User{UserLogin} || $UserID;
            push @Members, { ID => 0 + $UserID, Name => $Name };
        }
    }

    my $Change = $Kernel::OM->Get('Kernel::System::ITSMChange')->ChangeGet(
        ChangeID => $WorkOrder->{ChangeID}, UserID => $Self->{UserID},
    ) || {};
    my %Group = $GroupObject->GroupGet( ID => $Assignment->{GroupID} );
    my %ViewData = (
        WorkOrderID       => 0 + $WorkOrderID,
        WorkOrderNumber   => $WorkOrder->{WorkOrderNumber} || $WorkOrderID,
        WorkOrderTitle    => $WorkOrder->{WorkOrderTitle} || '',
        ChangeNumber      => $Change->{ChangeNumber} || '',
        ChangeTitle       => $Change->{ChangeTitle} || '',
        GroupName         => $Group{Name} || $Assignment->{GroupID},
        CanClaim          => $CanClaim,
        CanAssign         => $IsManager && @Members ? 1 : 0,
        Members           => \@Members,
        ChallengeToken    => $Layout->{UserChallengeToken},
    );
    my $Output = join '', $Layout->Header(), $Layout->NavigationBar();
    $Layout->Block( Name => 'Manage', Data => \%ViewData );
    $Output .= $Layout->Output( TemplateFile => 'AgentWorkordersToGroupManage', Data => \%ViewData );
    $Output .= $Layout->Footer();
    return $Output;
}

sub _IsManager {
    my ($Self) = @_;
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %RWGroups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
    for my $Name (qw(itsm-change-manager admin)) {
        my $ID = $GroupObject->GroupLookup( Group => $Name ) || next;
        return 1 if $RWGroups{$ID};
    }
    return;
}

1;
