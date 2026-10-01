# --
# Group-aware actions for ITSM Work Orders assigned to a team.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Group',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    return bless { %Param }, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $WorkOrder = $Param{WorkOrder} || return $Param{Counter};
    my $AssignmentObject = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my $Assignment = $AssignmentObject->Get( WorkOrderID => $WorkOrder->{WorkOrderID} )
        || return $Param{Counter};

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %RWGroups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
    my $CanClaim = $RWGroups{ $Assignment->{GroupID} }
        && !$Assignment->{ClaimedAgentID}
        && $AssignmentObject->CanTake( WorkOrderID => $WorkOrder->{WorkOrderID}, UserID => $Self->{UserID} );
    my $CanAssign = $Self->_IsManager() && $Self->_HasActiveMembers( GroupID => $Assignment->{GroupID} );
    return $Param{Counter} if !$CanClaim && !$CanAssign;

    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    $Layout->Block( Name => 'Menu' );
    $Layout->Block( Name => 'MenuItemSplit' ) if $Param{Counter};
    $Layout->Block(
        Name => 'MenuItem',
        Data => {
            %Param,
            %{$WorkOrder},
            %{ $Param{Config} || {} },
            Name        => 'Take or assign to group member',
            Description => 'Take or assign this group Work Order',
            Link        => 'Action=AgentWorkordersToGroupManage;WorkOrderID=' . $WorkOrder->{WorkOrderID},
            Target      => 'PopUp',
            MenuClass   => 'AsPopup',
        },
    );

    return ( $Param{Counter} || 0 ) + 1;
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

sub _HasActiveMembers {
    my ( $Self, %Param ) = @_;
    my %Members = $Kernel::OM->Get('Kernel::System::Group')->PermissionGroupGet(
        GroupID => $Param{GroupID}, Type => 'rw',
    );
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    for my $UserID ( keys %Members ) {
        my %User = $UserObject->GetUserData( UserID => $UserID, Valid => 1 );
        return 1 if $User{UserID};
    }
    return;
}

1;
