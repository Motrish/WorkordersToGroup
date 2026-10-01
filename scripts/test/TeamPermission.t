use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck;

our %Rights = (
    10 => { 3 => 1 },
    11 => {},
    12 => { 3 => 1 },
    13 => { 3 => 1, 8 => 1 },
);
our $ClaimedAgentID;
our $NativeAgentID;

{
    package Kernel;
    our $OM;
}

{
    package Local::OM;
    sub new { bless {}, shift }
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Assignment' if $Name eq 'Kernel::System::WorkordersToGroup::Assignment';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::WorkOrder' if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return bless {}, 'Local::Main' if $Name eq 'Kernel::System::Main';
        die "Unexpected dependency $Name";
    }
}

{
    package Local::Assignment;
    sub Get { return { WorkOrderID => $_[2], GroupID => 3, ClaimedAgentID => $main::ClaimedAgentID }; }
}
{
    package Local::Group;
    sub PermissionUserGet { return %{ $main::Rights{ $_[2] } || {} }; }
    sub GroupLookup { return $_[2] eq 'itsm-change-manager' ? 8 : 9; }
}
{
    package Local::User;
    sub GetUserData { return ( UserID => $_[2], ValidID => 1 ); }
}
{
    package Local::WorkOrder;
    sub WorkOrderGet { return { WorkOrderAgentID => $main::NativeAgentID }; }
}
{
    package Local::Main;
    sub Require { return 1; }
}

$Kernel::OM = Local::OM->new();
my $Check = Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck->new();

$ClaimedAgentID = undef;
$NativeAgentID = undef;
ok( $Check->Run( UserID => 10, Type => 'ro', WorkOrderID => 20 ), 'effective group ro member may view assignment' );
ok( !$Check->Run( UserID => 10, Type => 'rw', WorkOrderID => 20 ), 'unclaimed group member may not edit before claiming' );
ok( !$Check->Run( UserID => 10, Type => 'rw', WorkOrderID => 20, PermissionRegistry => 'ITSMWorkOrder::TakePermission' ), 'native take is denied for managed work orders' );
ok( !$Check->Run( UserID => 11, Type => 'ro', WorkOrderID => 20 ), 'non-member cannot view managed assignment' );

$ClaimedAgentID = 12;
$NativeAgentID = 12;
ok( $Check->Run( UserID => 12, Type => 'rw', WorkOrderID => 20 ), 'claimed agent with current rw group rights may edit' );
ok( !$Check->Run( UserID => 10, Type => 'rw', WorkOrderID => 20 ), 'another group member cannot edit a claimed order' );

$ClaimedAgentID = undef;
$NativeAgentID = undef;
ok( $Check->Run( UserID => 13, Type => 'rw', WorkOrderID => 20 ), 'Change Manager with effective rw membership has oversight' );

done_testing();
