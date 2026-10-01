use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::WorkordersToGroup::Assignment;
use Kernel::System::WorkordersToGroup::AtomicOperation;

{
    package Kernel;
    our $OM;
}

{
    package Local::Handle;
    sub new { return bless { AutoCommit => 1 }, $_[0]; }
    sub commit { $_[0]->{AutoCommit} = 1; return 1; }
}

{
    package Local::DB;
    sub new {
        my ($Class) = @_;
        my $Self = bless { Rows => {}, Audit => [], NextID => 1 }, $Class;
        $Self->{dbh} = Local::Handle->new();
        return $Self;
    }
    sub Connect { 1 }
    sub BeginWork { $_[0]->{dbh}->{AutoCommit} = 0; 1 }
    sub Rollback { $_[0]->{dbh}->{AutoCommit} = 1; 1 }
    sub Prepare {
        my ( $Self, %Param ) = @_;
        $Self->{SQL} = $Param{SQL};
        $Self->{Bind} = $Param{Bind} || [];
        if ( $Self->{RaceGroupChange} && $Self->{SQL} =~ /FOR UPDATE/ ) {
            $Self->{Rows}->{79}->{GroupID} = 6;
            $Self->{RaceGroupChange} = 0;
        }
        return 1;
    }
    sub FetchrowArray {
        my ($Self) = @_;
        my $ID = ${ $Self->{Bind}->[0] };
        return ($ID) if $Self->{SQL} =~ /FROM change_workorder/;
        my $Row = $Self->{Rows}->{$ID} || return;
        return @{$Row}{qw(ID WorkOrderID ChangeID GroupID ClaimedAgentID SourcePackage SourceKey Version)};
    }
    sub Do {
        my ( $Self, %Param ) = @_;
        my $SQL = $Param{SQL} || '';
        if ( $SQL =~ /^UPDATE wotg_assignment SET claimed_agent_id/ ) {
            return 1 if $Self->{NoClaimUpdate};
            my @Value = map { defined $_ ? $$_ : undef } @{ $Param{Bind} };
            my ( $AgentID, $ActorID, $ID ) = @Value;
            my ($Row) = grep { $_->{ID} == $ID } values %{ $Self->{Rows} };
            return if !$Row;
            return if $Row->{ClaimedAgentID};
            $Row->{ClaimedAgentID} = $AgentID;
            $Row->{Version}++;
            return 1;
        }
        if ( $SQL =~ /^INSERT INTO wotg_audit/ ) {
            push @{ $Self->{Audit} }, $Param{Bind};
            return 1;
        }
        return 1;
    }
}

{
    package Local::Cache;
    sub CleanUp { return 1; }
    sub Delete { return 1; }
}

{
    package Local::Config;
    sub Get { return; }
}

{
    package Local::OM;
    sub new { bless { DB => $_[1], StateTransitions => $_[2] }, $_[0] }
    sub Get {
        my ( $Self, $Name ) = @_;
        return $Self->{DB} if $Name eq 'Kernel::System::DB';
        return Kernel::System::WorkordersToGroup::AtomicOperation->new( DBObject => $Self->{DB} )
            if $Name eq 'Kernel::System::WorkordersToGroup::AtomicOperation';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::WorkOrder' if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return bless { Transitions => $Self->{StateTransitions} }, 'Local::StateMachine'
            if $Name eq 'Kernel::System::ITSMChange::ITSMStateMachine';
        return bless {}, 'Local::Cache' if $Name eq 'Kernel::System::Cache';
        die "Unexpected dependency $Name";
    }
}

{
    package Local::Group;
    sub GroupGet { return ( ID => $_[2], ValidID => 1, Name => 'Operations' ); }
    sub PermissionUserGet { return ( 5 => 'Operations' ); }
}

{
    package Local::User;
    sub GetUserData { return ( UserID => $_[2], ValidID => 1 ); }
}

{
    package Local::StateMachine;
    sub StateTransitionGet { return $_[0]->{Transitions}; }
}

{
    package Local::WorkOrder;
    our %Data;
    our @UpdateCalls;
    sub WorkOrderGet { return { %{ $Data{ $_[2] } || {} } }; }
    sub WorkOrderUpdate {
        my ( $Self, %Param ) = @_;
        push @UpdateCalls, { %Param };
        return if join( ',', sort keys %Param ) ne 'UserID,WorkOrderAgentID,WorkOrderID';
        $Data{ $Param{WorkOrderID} }->{WorkOrderAgentID} = $Param{WorkOrderAgentID};
        return 1;
    }
}

my $DB = Local::DB->new();
$DB->{Rows}->{77} = {
    ID => 1, WorkOrderID => 77, ChangeID => 31, GroupID => 5,
    ClaimedAgentID => undef, SourcePackage => '', SourceKey => '', Version => 1,
};
$DB->{Rows}->{78} = {
    ID => 2, WorkOrderID => 78, ChangeID => 31, GroupID => 5,
    ClaimedAgentID => undef, SourcePackage => '', SourceKey => '', Version => 1,
};
$DB->{Rows}->{79} = {
    ID => 3, WorkOrderID => 79, ChangeID => 31, GroupID => 5,
    ClaimedAgentID => undef, SourcePackage => '', SourceKey => '', Version => 1,
};
$DB->{Rows}->{80} = {
    ID => 4, WorkOrderID => 80, ChangeID => 31, GroupID => 5,
    ClaimedAgentID => undef, SourcePackage => '', SourceKey => '', Version => 1,
};
$Local::WorkOrder::Data{77} = { WorkOrderID => 77, WorkOrderStateID => 10, WorkOrderAgentID => undef };
$Local::WorkOrder::Data{78} = { WorkOrderID => 78, WorkOrderStateID => 10, WorkOrderAgentID => undef };
$Local::WorkOrder::Data{79} = { WorkOrderID => 79, WorkOrderStateID => 10, WorkOrderAgentID => undef };
$Local::WorkOrder::Data{80} = { WorkOrderID => 80, WorkOrderStateID => 10, WorkOrderAgentID => undef };
$Kernel::OM = Local::OM->new( $DB, [11] );
my $Assignment = Kernel::System::WorkordersToGroup::Assignment->new( DBObject => $DB );

my $Claim = $Assignment->Claim( WorkOrderID => 77, UserID => 7 );
ok( $Claim->{Success}, 'eligible group agent claims the Work Order' );
is( $DB->{Rows}->{77}->{ClaimedAgentID}, 7, 'the group mapping records the winning agent' );
is( $Local::WorkOrder::Data{77}->{WorkOrderAgentID}, 7, 'claim writes the native Work Order agent' );
is_deeply(
    [ sort keys %{ $Local::WorkOrder::UpdateCalls[0] } ],
    [qw(UserID WorkOrderAgentID WorkOrderID)],
    'native update receives only the intended agent fields',
);
is( scalar @{ $DB->{Audit} }, 1, 'successful claim writes an audit entry' );

$Kernel::OM = Local::OM->new( $DB, [0] );
my $Closed = $Assignment->Claim( WorkOrderID => 78, UserID => 7 );
ok( !$Closed->{Success}, 'terminal Work Order cannot be claimed' );
is( $Closed->{Code}, 'WORKORDER_NOT_TAKEABLE', 'terminal claim is rejected with a stable code' );
ok( !defined $DB->{Rows}->{78}->{ClaimedAgentID}, 'terminal rejection leaves assignment unchanged' );

$Kernel::OM = Local::OM->new( $DB, [11] );
$DB->{RaceGroupChange} = 1;
my $GroupRace = $Assignment->Claim( WorkOrderID => 79, UserID => 7 );
ok( !$GroupRace->{Success}, 'claim rechecks group permission after locking the current mapping' );
is( $GroupRace->{Code}, 'GROUP_PERMISSION_REQUIRED', 'group change race is rejected against the locked group' );
is( $DB->{Rows}->{79}->{GroupID}, 6, 'claim does not overwrite a concurrently moved group' );
ok( !defined $DB->{Rows}->{79}->{ClaimedAgentID}, 'claim race leaves the new group assignment unclaimed' );

$DB->{NoClaimUpdate} = 1;
my $FalsePositiveDo = $Assignment->Claim( WorkOrderID => 80, UserID => 7 );
$DB->{NoClaimUpdate} = 0;
ok( !$FalsePositiveDo->{Success}, 'SQL execution success without a version change is not treated as a successful claim' );
is( $FalsePositiveDo->{Code}, 'CONCURRENT_CHANGE', 'readback detects a no-op conditional update' );
ok( !defined $DB->{Rows}->{80}->{ClaimedAgentID}, 'failed no-op claim does not update the native Work Order' );

done_testing();
