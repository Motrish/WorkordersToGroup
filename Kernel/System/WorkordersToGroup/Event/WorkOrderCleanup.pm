# --
# Clean up assignment ownership after the native Work Order was deleted.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::System::WorkordersToGroup::Event::WorkOrderCleanup;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    return bless {}, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    return 1 if ( $Param{Event} || '' ) ne 'WorkOrderDeletePost';
    my $Data = ref $Param{Data} eq 'HASH' ? $Param{Data} : {};
    my $UserID = $Data->{UserID} || $Param{UserID};
    my $Result = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->WorkOrderDeleted(
        WorkOrderID => $Data->{WorkOrderID},
        UserID      => $UserID,
    );
    if ( !$Result || !$Result->{Success} ) {
        my $Code = ref $Result eq 'HASH' ? ( $Result->{Code} || 'UNKNOWN' ) : 'UNKNOWN';
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'WorkordersToGroup could not clean up the assignment for deleted WorkOrderID '
                . ( $Data->{WorkOrderID} || '<unknown>' ) . ': ' . $Code,
        );
        return;
    }
    return 1;
}

1;
