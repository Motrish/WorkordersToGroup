# --
# CSRF protected claim endpoint for group assigned Work Orders.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::AgentWorkordersToGroupTake;

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
    my $Result;

    if ( $WorkOrderID =~ /\A\d+\z/ ) {
        $Layout->ChallengeTokenCheck();
        $Result = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->Claim(
            WorkOrderID => $WorkOrderID,
            UserID      => $Self->{UserID},
        );
    }
    my $ResultHash = ref $Result eq 'HASH' ? $Result : undef;
    my $Code = $ResultHash && $ResultHash->{Code} ? $ResultHash->{Code} : 'INPUT_INVALID';

    if ( ( $Request->GetParam( Param => 'Ajax' ) || '' ) eq '1' ) {
        my $Data = {
            Success => $ResultHash && $ResultHash->{Success} ? 1 : 0,
            Code    => $ResultHash && $ResultHash->{Success} ? 'CLAIMED' : $Code,
        };
        return $Layout->Attachment(
            ContentType => 'application/json; charset=' . $Layout->{Charset},
            Content     => $Layout->JSONEncode( Data => $Data ),
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    if ( $ResultHash && $ResultHash->{Success} ) {
        my $ReturnView = $Request->GetParam( Param => 'ReturnView' ) || '';
        return $Layout->PopupClose(
            URL => $Self->{Session}{LastWorkOrderView}
                || "Action=AgentITSMWorkOrderZoom;WorkOrderID=$WorkOrderID",
        ) if $ReturnView eq 'workorder';
        my $Target = $ReturnView eq 'quick'
            ? 'Action=AgentWorkordersToGroup;Filter=unassigned;View=quick'
            : 'Action=AgentWorkordersToGroup;Filter=mine';
        return $Layout->Redirect( OP => $Target );
    }

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'notice',
        Message  => 'WorkordersToGroup claim rejected for WorkOrderID ' . ( $WorkOrderID || 'invalid' )
            . ' by UserID ' . ( $Self->{UserID} || 'unknown' )
            . ': ' . $Code,
    );
    return $Layout->Redirect( OP => 'Action=AgentWorkordersToGroup;Filter=unassigned;ClaimError=1' );
}

1;
