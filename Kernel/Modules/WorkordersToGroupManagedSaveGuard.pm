# --
# Block the native ITSM Work Order agent save route for managed assignments.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::WorkordersToGroupManagedSaveGuard;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Web::Request',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    return bless { %Param }, $Type;
}

sub PreRun {
    my ($Self) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Action = $Request->GetParam( Param => 'Action' ) || $Self->{Action} || '';
    my $Subaction = $Request->GetParam( Param => 'Subaction' ) || '';
    return if $Action ne 'AgentITSMWorkOrderAgent' || $Subaction ne 'Save';

    my $WorkOrderID = $Request->GetParam( Param => 'WorkOrderID' ) || '';
    my $Assignment = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->Get(
        WorkOrderID => $WorkOrderID,
    );
    return if !$Assignment;

    return $Kernel::OM->Get('Kernel::Output::HTML::Layout')->NoPermission( WithHeader => 'yes' );
}

1;
