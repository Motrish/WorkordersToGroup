# --
# General team view for group assigned ITSM Work Orders.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::AgentWorkordersToGroup;

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
    my $Filter = $Request->GetParam( Param => 'Filter' ) || 'all';
    $Filter = 'all' if $Filter !~ /\A(?:all|mine|unassigned)\z/;
    my $Subaction = $Request->GetParam( Param => 'Subaction' ) || '';
    return $Self->_QuickList() if $Subaction eq 'QuickList';
    my $View = $Request->GetParam( Param => 'View' ) || '';
    $View = '' if $View ne 'quick';
    my $Start = $Request->GetParam( Param => 'Start' ) || 0;
    $Start = 0 if $Start !~ /\A\d+\z/ || length($Start) > 15;
    my $CursorChangeTime = $Request->GetParam( Param => 'CursorChangeTime' ) || '';
    my $CursorID = $Request->GetParam( Param => 'CursorID' ) || '';
    my $CursorDirection = $Request->GetParam( Param => 'CursorDirection' ) || '';
    my $HasCursor = $View ne 'quick'
        && $CursorChangeTime =~ /\A\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\z/
        && $CursorID =~ /\A\d+\z/ && $CursorID > 0
        && $CursorDirection =~ /\A(?:next|previous)\z/;
    if ( !$HasCursor ) {
        ( $CursorChangeTime, $CursorID, $CursorDirection ) = ( '', '', '' );
    }
    else {
        $Start = 0;
    }
    my $PageSize = $View eq 'quick' ? 5 : 50;

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %Groups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'ro' );
    my %RWGroups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
    @Groups{ keys %RWGroups } = values %RWGroups;
    my %ValidGroups = $GroupObject->GroupList( Valid => 1 );
    delete $Groups{$_} for grep { !$ValidGroups{$_} } keys %Groups;
    my $IsManager = $Self->_IsManager();
    my @GroupIDs;
    if ( $Filter eq 'unassigned' ) {
        # Claiming requires write access. Read-only groups and manager-wide
        # visibility must not introduce non-claimable rows into this result.
        @GroupIDs = sort { $a <=> $b } grep { $ValidGroups{$_} } keys %RWGroups;
    }
    elsif ($IsManager) {
        my %All = $GroupObject->GroupList( Valid => 1 );
        @GroupIDs = sort { $a <=> $b } keys %All;
    }
    else {
        @GroupIDs = sort { $a <=> $b } keys %Groups;
    }

    my $AssignmentObject = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my $StateSignals = $Kernel::OM->Get('Kernel::Config')->Get('ITSMWorkOrder::State::Signal') || {};
    $StateSignals = {} if ref $StateSignals ne 'HASH';
    my @Rows;
    my %ChangeCache;
    my $HasNextPage = 0;
    my ( $HasPreviousPage, $NextCursor, $PreviousCursor ) = ( 0, {}, {} );
    if ( $View eq 'quick' ) {
        my $ListLimit = $View eq 'quick' ? 20 : $PageSize + 1;
        my $Items = $AssignmentObject->List(
            GroupIDs => \@GroupIDs, Filter => $Filter, UserID => $Self->{UserID},
            Limit => $ListLimit, Start => $Start,
        ) || [];
        for my $Item ( @{$Items} ) {
            my $Row = $Self->_RowFromItem(
                Item => $Item, GroupObject => $GroupObject, RWGroups => \%RWGroups,
                Filter => $Filter, ChangeCache => \%ChangeCache, StateSignals => $StateSignals,
            );
            push @Rows, $Row if $Row;
            last if @Rows >= $PageSize;
        }
    }
    else {
        my $Items = $AssignmentObject->List(
            GroupIDs => \@GroupIDs, Filter => $Filter, UserID => $Self->{UserID},
            Limit => $PageSize + 1,
            Start => $HasCursor ? 0 : $Start,
            CursorChangeTime => $CursorChangeTime,
            CursorID => $CursorID,
            CursorDirection => $CursorDirection,
        ) || [];
        my $HasMoreCandidates = @{$Items} > $PageSize ? 1 : 0;
        if ( $CursorDirection eq 'previous' && $HasMoreCandidates ) {
            # Previous is fetched in ascending order and reversed by List().
            # Its extra row is therefore the first (newest) candidate.
            shift @{$Items};
        }
        else {
            splice @{$Items}, $PageSize if @{$Items} > $PageSize;
        }
        if ( @{$Items} ) {
            my $First = $Items->[0];
            my $Last = $Items->[-1];
            $PreviousCursor = { ChangeTime => $First->{ChangeTime}, ID => $First->{ID} };
            $NextCursor = { ChangeTime => $Last->{ChangeTime}, ID => $Last->{ID} };
        }
        if ( $CursorDirection eq 'previous' ) {
            $HasPreviousPage = $HasMoreCandidates;
            $HasNextPage = 1;
        }
        else {
            $HasPreviousPage = $HasCursor || $Start ? 1 : 0;
            $HasNextPage = $HasMoreCandidates;
        }
        for my $Item ( @{$Items} ) {
            my $Row = $Self->_RowFromItem(
                Item => $Item, GroupObject => $GroupObject, RWGroups => \%RWGroups,
                Filter => $Filter, ChangeCache => \%ChangeCache, StateSignals => $StateSignals,
            );
            push @Rows, $Row if $Row;
        }
    }

    my %ViewData = (
        Filter       => $Filter,
        View         => $View,
        ClaimError   => $Request->GetParam( Param => 'ClaimError' ) ? 1 : 0,
        WorkOrders   => \@Rows,
        WorkOrderCount => scalar @Rows,
        HasWorkOrders => @Rows ? 1 : 0,
        IsManager    => $IsManager ? 1 : 0,
        HasNextPage => $HasNextPage,
        HasPreviousPage => $HasPreviousPage,
        NextStart => $Start + $PageSize,
        PreviousStart => $Start >= $PageSize ? $Start - $PageSize : 0,
        NextCursorChangeTime => $NextCursor->{ChangeTime} || '',
        NextCursorID => $NextCursor->{ID} || '',
        PreviousCursorChangeTime => $PreviousCursor->{ChangeTime} || '',
        PreviousCursorID => $PreviousCursor->{ID} || '',
    );
    my $Output = join '', $Layout->Header(), $Layout->NavigationBar();
    $Layout->Block( Name => 'Overview', Data => \%ViewData );
    $Output .= $Layout->Output( TemplateFile => 'AgentWorkordersToGroup', Data => \%ViewData );
    $Output .= $Layout->Footer();
    return $Output;
}

sub _QuickList {
    my ($Self) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my %Groups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
    my %ValidGroups = $GroupObject->GroupList( Valid => 1 );
    my @GroupIDs = sort { $a <=> $b } grep { $ValidGroups{$_} } keys %Groups;
    my $AssignmentObject = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my $Count = $AssignmentObject->CountUnassigned( GroupIDs => \@GroupIDs, UserID => $Self->{UserID} );
    my $Items = $AssignmentObject->List(
        GroupIDs => \@GroupIDs,
        Filter   => 'unassigned',
        Limit    => 5,
    ) || [];
    my @Rows;
    my %ChangeCache;
    for my $Item ( @{$Items} ) {
        next if !$AssignmentObject->CanTake( WorkOrderID => $Item->{WorkOrderID}, UserID => $Self->{UserID} );
        my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
            WorkOrderID => $Item->{WorkOrderID}, UserID => $Self->{UserID},
        ) || next;
        my %Group = $GroupObject->GroupGet( ID => $Item->{GroupID} );
        my $Change = $Self->_ChangeInfo( $Item->{ChangeID}, \%ChangeCache );
        push @Rows, {
            WorkOrderID    => 0 + $Item->{WorkOrderID},
            WorkOrderTitle => $WorkOrder->{WorkOrderTitle} || '',
            WorkOrderNumber => $WorkOrder->{WorkOrderNumber} || $Item->{WorkOrderID},
            GroupName      => $Group{Name} || $Item->{GroupID},
            ChangeID       => 0 + ( $Item->{ChangeID} || 0 ),
            ChangeNumber   => $Change->{ChangeNumber} || '',
            ChangeTitle    => $Change->{ChangeTitle} || '',
        };
        last if @Rows >= 5;
    }
    my $Data = {
        Success         => 1,
        Count           => 0 + $Count,
        Items           => \@Rows,
        ClaimToken      => $Layout->{UserChallengeToken},
        Title           => $Layout->{LanguageObject}->Translate('Group Work Orders'),
        EmptyLabel      => $Layout->{LanguageObject}->Translate('No group Work Orders are available to claim.'),
        LoadingLabel    => $Layout->{LanguageObject}->Translate('Loading group Work Orders.'),
        LoadErrorLabel  => $Layout->{LanguageObject}->Translate('The group Work Orders could not be loaded.'),
        ClaimLabel      => $Layout->{LanguageObject}->Translate('Claim'),
        AllLabel        => $Layout->{LanguageObject}->Translate('All group Work Orders'),
        ClaimedLabel    => $Layout->{LanguageObject}->Translate('Work Order claimed.'),
        ConflictLabel   => $Layout->{LanguageObject}->Translate('This Work Order could not be claimed or is no longer available.'),
        SessionName     => $Layout->{SessionName},
        SessionID       => $Layout->{SessionID},
    };
    return $Layout->Attachment(
        ContentType => 'application/json; charset=' . $Layout->{Charset},
        Content     => $Layout->JSONEncode( Data => $Data ),
        Type        => 'inline',
        NoCache     => 1,
    );
}

sub _RowFromItem {
    my ( $Self, %Param ) = @_;
    my $Item = $Param{Item};
    my %Group = $Param{GroupObject}->GroupGet( ID => $Item->{GroupID} );
    my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
        WorkOrderID => $Item->{WorkOrderID}, UserID => $Self->{UserID},
    ) || return;
    my $AgentName = '';
    my $AgentID = $Item->{ClaimedAgentID} || $WorkOrder->{WorkOrderAgentID};
    if ($AgentID) {
        my %Agent = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $AgentID, Valid => 0 );
        $AgentName = join ' ', grep { $_ } @Agent{qw(UserFirstname UserLastname)};
        $AgentName ||= $Agent{UserLogin} || $AgentID;
    }
    my $CanTake = $Param{RWGroups}->{ $Item->{GroupID} }
        && !$Item->{ClaimedAgentID}
        && $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->CanTake(
            WorkOrderID => $Item->{WorkOrderID}, UserID => $Self->{UserID},
        ) ? 1 : 0;
    return if $Param{Filter} eq 'unassigned' && !$CanTake;
    my $Change = $Self->_ChangeInfo( $Item->{ChangeID}, $Param{ChangeCache} );
    my $Instruction = $WorkOrder->{InstructionPlain} || '';
    my $State = $WorkOrder->{WorkOrderState} || '';
    $Instruction =~ s/\s+/ /g;
    $Instruction =~ s/\A\s+|\s+\z//g;
    $Instruction = substr( $Instruction, 0, 160 ) . '…' if length $Instruction > 160;
    return {
        %{$Item},
        GroupName      => $Group{Name} || $Item->{GroupID},
        WorkOrderTitle => $WorkOrder->{WorkOrderTitle} || '',
        WorkOrderNumber => $WorkOrder->{WorkOrderNumber} || '',
        InstructionExcerpt => $Instruction,
        PlannedStartTime => $WorkOrder->{PlannedStartTime} || '',
        PlannedEndTime   => $WorkOrder->{PlannedEndTime} || '',
        WorkOrderState => $State,
        WorkOrderStateSignal => $Param{StateSignals}->{$State} || '',
        WorkOrderAgent => $AgentName,
        ChangeNumber   => $Change->{ChangeNumber} || '',
        ChangeTitle    => $Change->{ChangeTitle} || '',
        CanTake        => $CanTake,
        HasChange      => $Item->{ChangeID} ? 1 : 0,
    };
}

sub _ChangeInfo {
    my ( $Self, $ChangeID, $Cache ) = @_;
    return {} if !$ChangeID;
    $Cache ||= {};
    return $Cache->{$ChangeID} if exists $Cache->{$ChangeID};
    $Cache->{$ChangeID} = $Kernel::OM->Get('Kernel::System::ITSMChange')->ChangeGet(
        ChangeID => $ChangeID,
        UserID   => $Self->{UserID},
    ) || {};
    return $Cache->{$ChangeID};
}

sub _IsManager {
    my ($Self) = @_;
    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    for my $Name (qw(itsm-change-manager admin)) {
        my $ID = $GroupObject->GroupLookup( Group => $Name ) || next;
        my %Groups = $GroupObject->PermissionUserGet( UserID => $Self->{UserID}, Type => 'rw' );
        return 1 if $Groups{$ID};
    }
    return;
}

1;
