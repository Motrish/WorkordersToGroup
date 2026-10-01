# --
# Admin assignment, import, and group-change screen.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Modules::AdminWorkordersToGroup;

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
    my $Assignment = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment');
    my $Subaction = $Request->GetParam( Param => 'Subaction' ) || '';
    my ( $Notice, $Error, $LegacyPreview, $LegacyApplyResult ) = ( '', '', undef, undef );

    if ( $Subaction =~ /\A(?:Assign|ChangeGroup|Reassign|Release|Remove|PreviewLegacy|ApplyLegacy)\z/ ) {
        $Layout->ChallengeTokenCheck();
        if ( $Subaction eq 'Assign' ) {
            my $Result = $Assignment->Assign(
                WorkOrderID   => $Request->GetParam( Param => 'WorkOrderID' ) || '',
                GroupID       => $Request->GetParam( Param => 'GroupID' ) || '',
                UserID        => $Self->{UserID},
                SourcePackage => 'AdminWorkordersToGroup',
            );
            $Self->_Success($Result) ? ( $Notice = 'Der Arbeitsauftrag wurde der Gruppe zugeordnet.' )
                : ( $Error = 'Zuordnung fehlgeschlagen: ' . $Self->_ResultCode($Result) );
        }
        elsif ( $Subaction eq 'ChangeGroup' ) {
            my $Result = $Assignment->ChangeGroup(
                WorkOrderID  => $Request->GetParam( Param => 'WorkOrderID' ) || '',
                GroupID      => $Request->GetParam( Param => 'GroupID' ) || '',
                ReleaseAgent => $Request->GetParam( Param => 'ReleaseAgent' ) ? 1 : 0,
                UserID       => $Self->{UserID},
            );
            $Self->_Success($Result) ? ( $Notice = 'Die Gruppenzuordnung wurde geändert.' )
                : ( $Error = 'Gruppenwechsel fehlgeschlagen: ' . $Self->_ResultCode($Result) );
        }
        elsif ( $Subaction eq 'Reassign' ) {
            my $Result = $Assignment->ReassignAgent(
                WorkOrderID => $Request->GetParam( Param => 'WorkOrderID' ) || '',
                TargetUserID => $Request->GetParam( Param => 'TargetUserID' ) || '',
                UserID => $Self->{UserID},
            );
            $Self->_Success($Result) ? ( $Notice = 'Der Arbeitsauftrag wurde neu zugewiesen.' )
                : ( $Error = 'Neuzuweisung fehlgeschlagen: ' . $Self->_ResultCode($Result) );
        }
        elsif ( $Subaction eq 'Release' ) {
            my $Result = $Assignment->Release(
                WorkOrderID => $Request->GetParam( Param => 'WorkOrderID' ) || '',
                UserID      => $Self->{UserID},
            );
            $Self->_Success($Result) ? ( $Notice = 'Der Arbeitsauftrag ist wieder zur Übernahme frei.' )
                : ( $Error = 'Freigabe fehlgeschlagen: ' . $Self->_ResultCode($Result) );
        }
        elsif ( $Subaction eq 'Remove' ) {
            my $Result = $Assignment->Remove(
                WorkOrderID => $Request->GetParam( Param => 'WorkOrderID' ) || '',
                UserID      => $Self->{UserID},
            );
            $Self->_Success($Result) ? ( $Notice = 'Die Gruppenzuordnung wurde entfernt.' )
                : ( $Error = 'Entfernen fehlgeschlagen: ' . $Self->_ResultCode($Result) );
        }
        elsif ( $Subaction eq 'PreviewLegacy' ) {
            $LegacyPreview = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Migration')->Preview(
                UserID => $Self->{UserID},
            );
            $LegacyPreview ? ( $Notice = 'Vorschau erstellt. Es wurden noch keine Zuordnungen geändert.' )
                : ( $Error = 'Die Vorschau konnte nicht erstellt werden. Prüfe, ob CustomChangeAutomation installiert ist.' );
        }
        elsif ( $Subaction eq 'ApplyLegacy' ) {
            my $Result = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Migration')->Apply(
                UserID => $Self->{UserID},
            );
            if ( $Self->_Success($Result) ) {
                my $Counts = ref $Result->{Counts} eq 'HASH' ? $Result->{Counts} : {};
                $Notice = "Migration abgeschlossen: $Counts->{Created} angelegt, $Counts->{Existing} bereits vorhanden.";
            }
            elsif ( ref $Result eq 'HASH' && ref $Result->{Preview} eq 'HASH' ) {
                $LegacyPreview = $Result->{Preview};
                $Error = 'Migration gestoppt. Die Vorschau enthält Gruppenkonflikte oder ungültige Quellzeilen.';
            }
            elsif ( ref $Result eq 'HASH' ) {
                $LegacyApplyResult = $Result;
                $Error = 'Migration nicht vollständig. Fortschritt und Fehlerdetails stehen in der Ergebnisübersicht.';
            }
            else {
                $Error = 'Migration nicht vollständig. Details im OTOBO-Protokoll prüfen.';
            }
        }
    }

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $AuditWorkOrderID = $Request->GetParam( Param => 'AuditWorkOrderID' ) || '';
    my $AuditRows = $AuditWorkOrderID =~ /\A\d+\z/
        ? ( $Assignment->AuditList( WorkOrderID => $AuditWorkOrderID, Limit => 100 ) || [] )
        : [];
    my %GroupList = $GroupObject->GroupList( Valid => 1 );
    my $AssignableGroupIDs = $Assignment->AssignableGroupIDs();
    my @Groups = map { { ID => $_, Name => $GroupList{$_} } }
        grep { exists $GroupList{$_} } @{$AssignableGroupIDs};
    my $Assignments = $Assignment->ListAll( Limit => 1000 ) || [];
    my @Rows;
    for my $Item ( @{$Assignments} ) {
        my $GroupName = $GroupList{ $Item->{GroupID} } || $Item->{GroupID};
        my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
            WorkOrderID => $Item->{WorkOrderID}, UserID => $Self->{UserID},
        );
        push @Rows, {
            %{$Item},
            GroupName => $GroupName,
            WorkOrderTitle => $WorkOrder ? ( $WorkOrder->{WorkOrderTitle} || '' ) : '',
            WorkOrderState => $WorkOrder ? ( $WorkOrder->{WorkOrderState} || '' ) : '',
            NativeAgentID => $WorkOrder ? ( $WorkOrder->{WorkOrderAgentID} || '' ) : '',
            HasAgentMismatch => $WorkOrder && ( ( $WorkOrder->{WorkOrderAgentID} || 0 ) != ( $Item->{ClaimedAgentID} || 0 ) ) ? 1 : 0,
            HasWorkOrder => $WorkOrder ? 1 : 0,
        };
    }

    $LegacyPreview = undef if ref $LegacyPreview ne 'HASH';
    my $PreviewRows = $LegacyPreview && ref $LegacyPreview->{Rows} eq 'ARRAY'
        ? $LegacyPreview->{Rows} : [];
    my $PreviewCounts = $LegacyPreview && ref $LegacyPreview->{Counts} eq 'HASH'
        ? $LegacyPreview->{Counts} : {};
    my $LegacyIssues = [ grep { $_->{Status} eq 'GROUP_CONFLICT' || $_->{Status} eq 'SOURCE_INVALID' || $_->{Status} eq 'GROUP_NOT_ASSIGNABLE' } @{$PreviewRows} ];
    splice @{$LegacyIssues}, 100 if @{$LegacyIssues} > 100;
    my $LegacyApplyIssues = $LegacyApplyResult && ref $LegacyApplyResult->{Issues} eq 'ARRAY'
        ? [ @{ $LegacyApplyResult->{Issues} } ] : [];
    splice @{$LegacyApplyIssues}, 100 if @{$LegacyApplyIssues} > 100;
    my $Output = join '', $Layout->Header(), $Layout->NavigationBar();
    $Output .= $Layout->Notify( Info => $Notice ) if $Notice;
    $Output .= $Layout->Notify( Priority => 'Error', Info => $Error ) if $Error;
    my %ViewData = (
        Groups => \@Groups,
        HasAssignableGroups => @Groups ? 1 : 0,
        Assignments => \@Rows,
        HasAssignments => @Rows ? 1 : 0,
        AuditWorkOrderID => $AuditWorkOrderID,
        AuditRows => $AuditRows,
        HasAudit => @{$AuditRows} ? 1 : 0,
        LegacyPreview => $LegacyPreview,
        HasLegacyPreview => $LegacyPreview && @{$PreviewRows} ? 1 : 0,
        CanApplyLegacy => $LegacyPreview && !$PreviewCounts->{Conflict} && !$PreviewCounts->{Invalid} ? 1 : 0,
        LegacyIssues => $LegacyIssues,
        HasLegacyIssues => @{$LegacyIssues} ? 1 : 0,
        LegacyApplyResult => $LegacyApplyResult,
        HasLegacyApplyResult => ref $LegacyApplyResult eq 'HASH' ? 1 : 0,
        LegacyApplyCounts => $LegacyApplyResult && ref $LegacyApplyResult->{Counts} eq 'HASH'
            ? $LegacyApplyResult->{Counts} : {},
        LegacyApplyIssues => $LegacyApplyIssues,
        HasLegacyApplyIssues => @{$LegacyApplyIssues} ? 1 : 0,
    );
    $Layout->Block( Name => 'Overview', Data => \%ViewData );
    $Output .= $Layout->Output( TemplateFile => 'AdminWorkordersToGroup', Data => \%ViewData );
    $Output .= $Layout->Footer();
    return $Output;
}

sub _ResultCode {
    my ( $Self, $Result ) = @_;
    return ref $Result eq 'HASH' && $Result->{Code} ? $Result->{Code} : 'OPERATION_FAILED';
}

sub _Success {
    my ( $Self, $Result ) = @_;
    return ref $Result eq 'HASH' && $Result->{Success} ? 1 : 0;
}

1;
