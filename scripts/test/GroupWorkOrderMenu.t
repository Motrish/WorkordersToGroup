use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup;

{
    package Kernel;
    our $OM;
}

our $ActorID;
our $HasAssignment;
our $CanTake;
our $ClaimedAgentID;
our @Blocks;

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Assignment' if $Name eq 'Kernel::System::WorkordersToGroup::Assignment';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::Layout' if $Name eq 'Kernel::Output::HTML::Layout';
        die "Unexpected dependency $Name";
    }
}
{
    package Local::Assignment;
    sub Get { return if !$main::HasAssignment; return { GroupID => 10, ClaimedAgentID => $main::ClaimedAgentID }; }
    sub CanTake { return $main::CanTake; }
}
{
    package Local::Group;
    sub PermissionUserGet {
        return ( 10 => 'Operations' ) if $main::ActorID == 7;
        return ( 99 => 'itsm-change-manager' ) if $main::ActorID == 8;
        return ();
    }
    sub GroupLookup { return $_[2] eq 'itsm-change-manager' ? 99 : 100; }
    sub PermissionGroupGet { return ( 88 => 'Agent' ); }
}
{
    package Local::User;
    sub GetUserData { return ( UserID => $_[2], UserLogin => 'agent' ); }
}
{
    package Local::Layout;
    sub Block { my ( $Self, %Param ) = @_; push @main::Blocks, \%Param; return 1; }
}

$Kernel::OM = bless {}, 'Local::OM';
my $Menu = Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup->new( UserID => 7 );
my %Param = (
    Counter => 0,
    WorkOrder => { WorkOrderID => 41 },
    Config => { Name => 'Take or assign this ticket' },
    MenuID => '036-WorkordersToGroup',
);

$HasAssignment = 0;
is( $Menu->Run(%Param), 0, 'orders without a group assignment get no additional action' );
is( scalar @Blocks, 0, 'unmanaged work orders add no menu item' );

$HasAssignment = 1;
$CanTake = 1;
$ClaimedAgentID = undef;
$ActorID = 7;
my $MemberMenu = Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup->new( UserID => $ActorID );
is( $MemberMenu->Run(%Param), 1, 'writable group member sees the claim action' );
is( $Blocks[-1]->{Data}->{Link}, 'Action=AgentWorkordersToGroupManage;WorkOrderID=41', 'action opens the group-aware popup for this work order' );
is( $Blocks[-1]->{Data}->{Target}, 'PopUp', 'group action opens in the work order popup' );

@Blocks = ();
$ActorID = 9;
my $OtherMenu = Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup->new( UserID => $ActorID );
is( $OtherMenu->Run(%Param), 0, 'unrelated agents do not see the group action' );

@Blocks = ();
$ActorID = 8;
$ClaimedAgentID = 7;
$CanTake = 0;
my $ManagerMenu = Kernel::Output::HTML::ITSMWorkOrder::MenuWorkordersToGroup->new( UserID => $ActorID );
is( $ManagerMenu->Run(%Param), 1, 'Change Manager sees the reassignment action for claimed orders' );

done_testing();
