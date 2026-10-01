# --
# Header counter for unassigned group Work Orders.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Output::HTML::ToolBar::GroupWorkOrders;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Group',
    'Kernel::System::WorkordersToGroup::Assignment',
);

sub new {
    my ( $Type, %Param ) = @_;
    my $Self = {};
    bless $Self, $Type;
    $Self->{UserID} = $Param{UserID} || 0;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    return if !$Self->{UserID};

    my $Action = 'AgentWorkordersToGroup';
    my $ActionEnabled = 1;
    my $Count = 0;
    my $Failure;

    # This module is part of the global agent toolbar. A query or permission
    # failure here must not turn every agent page into an Internal Server Error.
    # Fail closed with a zero badge and log the underlying exception.
    {
        local $@;
        my $OK = eval {
            my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
            my $FrontendModules = $ConfigObject->Get('Frontend::Module') || {};
            $ActionEnabled = ref $FrontendModules eq 'HASH' && $FrontendModules->{$Action} ? 1 : 0;

            if ($ActionEnabled) {
                my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
                my %WritableGroups = $GroupObject->PermissionUserGet(
                    UserID => $Self->{UserID},
                    Type   => 'rw',
                );
                my %ValidGroups = $GroupObject->GroupList( Valid => 1 );
                my @GroupIDs = grep { $ValidGroups{$_} } keys %WritableGroups;
                $Count = $Kernel::OM->Get('Kernel::System::WorkordersToGroup::Assignment')->CountUnassigned(
                    GroupIDs => \@GroupIDs,
                    UserID   => $Self->{UserID},
                );
                $Count = 0 if !defined $Count || $Count !~ /\A\d+\z/;
            }
            1;
        };
        $Failure = $@ if !$OK;
    }

    return if !$ActionEnabled && !$Failure;

    if ($Failure) {
        $Failure =~ s/\s+\z//;
        eval {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "WorkordersToGroup toolbar failed closed for UserID $Self->{UserID}: $Failure",
            );
        };
        $Count = 0;
    }

    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ToolbarConfig = $Param{Config} || {};
    my $Priority = $ToolbarConfig->{Priority} || 1000650;
    my %Return = (
        $Priority => {
            Block       => 'ToolBarItem',
            Description => $Layout->{LanguageObject}->Translate('Group Work Orders available to claim'),
            Count       => $Count,
            Class       => $ToolbarConfig->{CssClass} || 'WorkordersToGroup',
            Icon        => $ToolbarConfig->{Icon} || 'fa fa-users',
            Link        => $Layout->{Baselink} . 'Action=AgentWorkordersToGroup;Filter=unassigned',
            AccessKey   => '',
        },
    );
    return %Return;
}

1;
