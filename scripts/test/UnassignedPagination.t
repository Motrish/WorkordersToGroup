use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::Modules::AgentWorkordersToGroup;

{
    package Kernel;
    our $OM;
}

our %Params;
our $ChangeGetCalls = 0;

{
    package Local::Config;
    sub Get { return { ready => 'yellowled' }; }
}

{
    package Local::Request;
    sub GetParam { return $main::Params{ $_[2] }; }
}

{
    package Local::Layout;
    sub new { bless {}, $_[0]; }
    sub Header { return ''; }
    sub NavigationBar { return ''; }
    sub Footer { return ''; }
    sub Block { my ( $Self, %Param ) = @_; $Self->{Data} = $Param{Data}; return 1; }
    sub Output { return ''; }
}

{
    package Local::Group;
    sub PermissionUserGet {
        my ( $Self, %Param ) = @_;
        return ( 5 => 'Read Only' ) if $Param{Type} eq 'ro';
        return ( 6 => 'Writable' );
    }
    sub GroupList { return ( 5 => 'Read Only', 6 => 'Writable' ); }
    sub GroupLookup { return; }
    sub GroupGet { return ( ID => $_[2], Name => 'Writable' ); }
}

{
    package Local::Assignment;
    our @Items;
    our @GroupIDs;
    our @Calls;
    our %CanTake;
    sub List {
        my ( $Self, %Param ) = @_;
        @GroupIDs = @{ $Param{GroupIDs} };
        push @Calls, { Start => $Param{Start}, Limit => $Param{Limit} };
        my $Start = $Param{Start} || 0;
        my $End = $Start + $Param{Limit} - 1;
        $End = $#Items if $End > $#Items;
        return [] if $Start > $#Items;
        return [ @Items[ $Start .. $End ] ];
    }
    sub CanTake { return $CanTake{ $_[2] } ? 1 : 0; }
}

{
    package Local::WorkOrder;
    sub WorkOrderGet { return { WorkOrderID => $_[2], WorkOrderNumber => 3, WorkOrderTitle => 'Task', WorkOrderState => 'ready' }; }
}

{
    package Local::User;
    sub GetUserData { return; }
}

{
    package Local::Change;
    sub ChangeGet { $main::ChangeGetCalls++; return { ChangeNumber => 'CH0001', ChangeTitle => 'Network rollout' }; }
}

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Request' if $Name eq 'Kernel::System::Web::Request';
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return $Self->{Layout} if $Name eq 'Kernel::Output::HTML::Layout';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::Assignment' if $Name eq 'Kernel::System::WorkordersToGroup::Assignment';
        return bless {}, 'Local::WorkOrder' if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::Change' if $Name eq 'Kernel::System::ITSMChange';
        die "Unexpected dependency $Name";
    }
}

sub RunView {
    my (%Param) = @_;
    %Params = ( Filter => 'unassigned', %Param );
    my $Layout = Local::Layout->new();
    $Kernel::OM = bless { Layout => $Layout }, 'Local::OM';
    my $Module = Kernel::Modules::AgentWorkordersToGroup->new( UserID => 7 );
    $Module->Run();
    return $Layout->{Data};
}

@Local::Assignment::Items = map {
    { ID => $_, WorkOrderID => 1000 + $_, ChangeID => 10, GroupID => 6, ClaimedAgentID => undef }
} 1 .. 52;
%Local::Assignment::CanTake = map { ( 1000 + $_ ) => ( $_ == 1 ? 0 : 1 ) } 1 .. 52;
my $PageWithMore = RunView( Start => 0 );
is_deeply( \@Local::Assignment::GroupIDs, [ 6 ], 'unassigned list is scoped to the agent write groups only' );
is( scalar @{ $PageWithMore->{WorkOrders} }, 49, 'page filters a stale unclaimable row from its 50 database candidates' );
is( $PageWithMore->{WorkOrders}->[0]->{WorkOrderID}, 1002, 'unclaimable row is removed before the page is formed' );
ok( $PageWithMore->{HasNextPage}, 'next page is based on an extra database candidate' );
is( scalar @Local::Assignment::Calls, 1, 'one bounded database page is fetched without rehydrating earlier chunks' );
is( $Local::Assignment::Calls[0]->{Start}, 0, 'first page starts at database offset zero' );
is( $PageWithMore->{WorkOrders}->[0]->{ChangeNumber}, 'CH0001', 'list row uses the change number from ChangeGet' );
is( $PageWithMore->{WorkOrders}->[0]->{ChangeTitle}, 'Network rollout', 'list row uses the change title from ChangeGet' );
is( $PageWithMore->{WorkOrders}->[0]->{WorkOrderNumber}, 3, 'list row includes the native Work Order number' );
is( $PageWithMore->{WorkOrders}->[0]->{WorkOrderStateSignal}, 'yellowled', 'list row uses the configured state color signal' );
is( $ChangeGetCalls, 1, 'one ChangeGet lookup is shared by every row for the same change' );

@Local::Assignment::Items = @Local::Assignment::Items[ 0 .. 50 ];
my $PageWithoutMore = RunView( Start => 0 );
is( scalar @{ $PageWithoutMore->{WorkOrders} }, 49, 'last page contains only visible rows from its database page' );
ok( $PageWithoutMore->{HasNextPage}, 'the extra claimable database row remains reachable on the next page' );

@Local::Assignment::Items = @Local::Assignment::Items[ 0 .. 49 ];
my $PageAtEnd = RunView( Start => 0 );
ok( !$PageAtEnd->{HasNextPage}, 'page without an extra database row has no Next link' );

@Local::Assignment::Items = map {
    { ID => $_, WorkOrderID => 1000 + $_, ChangeID => 10, GroupID => 6, ClaimedAgentID => undef }
} 1 .. 52;
my $PageTwo = RunView( Start => 50 );
is( $Local::Assignment::Calls[-1]->{Start}, 50, 'later pages query their own offset directly' );
is( scalar @{ $PageTwo->{WorkOrders} }, 2, 'later page contains only its remaining rows without rescanning page one' );

done_testing();
