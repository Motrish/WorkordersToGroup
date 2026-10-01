# --
# Group scoped access for Work Orders registered in WorkordersToGroup.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Group',
    'Kernel::Config',
    'Kernel::System::ITSMChange::ITSMWorkOrder',
    'Kernel::System::Main',
    'Kernel::System::User',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    return bless {}, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    return if !$Param{UserID} || !$Param{WorkOrderID} || !$Param{Type};

    my $Registry = $Param{PermissionRegistry} || 'ITSMWorkOrder::Permission';
    my $Assignment = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->Get(
        WorkOrderID => $Param{WorkOrderID},
    );
    return $Self->_NativePermissions(%Param) if !$Assignment;

    my %User = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $Param{UserID}, Valid => 1 );
    return if !$User{UserID};

    # All native take requests for managed items go through our POST action,
    # which performs the atomic claim and updates the native Work Order.
    return if $Registry eq 'ITSMWorkOrder::TakePermission';

    return 1 if $Self->_IsManager( UserID => $Param{UserID} );
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %Groups = $GroupObject->PermissionUserGet(
        UserID => $Param{UserID},
        Type   => $Param{Type} eq 'ro' ? 'ro' : 'rw',
    );
    if ( $Param{Type} eq 'ro' ) {
        my %RWGroups = $GroupObject->PermissionUserGet( UserID => $Param{UserID}, Type => 'rw' );
        @Groups{ keys %RWGroups } = values %RWGroups;
    }
    return if !$Groups{ $Assignment->{GroupID} };

    return 1 if $Param{Type} eq 'ro';
    return if !$Assignment->{ClaimedAgentID} || $Assignment->{ClaimedAgentID} != $Param{UserID};

    my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
        WorkOrderID => $Param{WorkOrderID},
        UserID      => $Param{UserID},
    );
    return if !$WorkOrder || !$WorkOrder->{WorkOrderAgentID};
    return $WorkOrder->{WorkOrderAgentID} == $Param{UserID} ? 1 : undef;
}

sub _IsManager {
    my ( $Self, %Param ) = @_;
    for my $GroupName (qw(itsm-change-manager admin)) {
        my $GroupID = $Kernel::OM->Get('Kernel::System::Group')->GroupLookup( Group => $GroupName ) || next;
        my %Groups = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Param{UserID}, Type => 'rw',
        );
        return 1 if $Groups{$GroupID};
    }
    return;
}

sub _NativePermissions {
    my ( $Self, %Param ) = @_;
    my $Registry = $Param{PermissionRegistry} || 'ITSMWorkOrder::Permission';
    my $Modules = $Kernel::OM->Get('Kernel::Config')->Get($Registry);
    return if ref $Modules ne 'HASH';

    MODULE:
    for my $Key ( sort keys %{$Modules} ) {
        my $Entry = $Modules->{$Key};
        next MODULE if ref $Entry ne 'HASH' || !$Entry->{Module};
        next MODULE if $Entry->{Module} eq __PACKAGE__;
        my $Module = $Entry->{Module};
        next MODULE if !$Kernel::OM->Get('Kernel::System::Main')->Require($Module);

        my $Access = $Module->new()->Run(%Param);
        return 1 if $Access && $Entry->{Granted};
        return if !$Access && $Entry->{Required};
    }

    # Match OTOBO's default-deny behavior when no permission check granted.
    return;
}

1;
