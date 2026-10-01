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
        my $Self = bless { Rows => {}, Audit => [], NextID => 1, AutoCommit => 1 }, shift;
        $Self->{dbh} = Local::Handle->new();
        return $Self;
    }
    sub Connect { 1 }
    sub BeginWork { $_[0]->{AutoCommit} = 0; $_[0]->{dbh}->{AutoCommit} = 0; 1 }
    sub Rollback { $_[0]->{AutoCommit} = 1; $_[0]->{dbh}->{AutoCommit} = 1; $_[0]->{Rows} = $_[0]->{BeforeRows} if $_[0]->{BeforeRows}; 1 }
    sub Prepare {
        my ( $Self, %Param ) = @_;
        $Self->{SQL} = $Param{SQL};
        $Self->{Bind} = $Param{Bind} || [];
        return 1;
    }
    sub FetchrowArray {
        my ($Self) = @_;
        my $WorkOrderID = ${ $Self->{Bind}->[0] };
        return ($WorkOrderID) if $Self->{SQL} =~ /FROM change_workorder/;
        my $Row = $Self->{Rows}->{$WorkOrderID} || return;
        return @{$Row}{qw(ID WorkOrderID ChangeID GroupID ClaimedAgentID SourcePackage SourceKey Version)};
    }
    sub Do {
        my ( $Self, %Param ) = @_;
        my $SQL = $Param{SQL} || '';
        if ( $SQL =~ /^INSERT INTO wotg_assignment/ ) {
            my @V = map { defined $_ ? $$_ : undef } @{ $Param{Bind} };
            my $WorkOrderID = $V[0];
            return if $Self->{Rows}->{$WorkOrderID};
            $Self->{Rows}->{$WorkOrderID} = {
                ID => $Self->{NextID}++, WorkOrderID => $WorkOrderID, ChangeID => $V[1], GroupID => $V[2],
                ClaimedAgentID => $V[3], SourcePackage => $V[4], SourceKey => $V[5], Version => 1,
            };
            return 1;
        }
        if ( $SQL =~ /^INSERT INTO wotg_audit/ ) {
            push @{ $Self->{Audit} }, $SQL;
            return 1;
        }
        if ( $SQL =~ /^DELETE FROM wotg_assignment/ ) {
            my ( $ID ) = map { defined $_ ? $$_ : undef } @{ $Param{Bind} };
            my ($WorkOrderID) = map { $_->{WorkOrderID} }
                grep { $_->{ID} == $ID } values %{ $Self->{Rows} };
            delete $Self->{Rows}->{$WorkOrderID} if $WorkOrderID;
            return 1;
        }
        if ( $SQL eq 'ROLLBACK' ) {
            return $Self->Rollback();
        }
        if ( $SQL =~ /SAVEPOINT|RELEASE SAVEPOINT/ ) { return 1 }
        return 1;
    }
}

{
    package Local::OM;
    sub new { bless { DB => $_[1] }, $_[0] }
    sub Get {
        my ( $Self, $Name ) = @_;
        return $Self->{DB} if $Name eq 'Kernel::System::DB';
        return Kernel::System::WorkordersToGroup::AtomicOperation->new( DBObject => $Self->{DB} )
            if $Name eq 'Kernel::System::WorkordersToGroup::AtomicOperation';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::WorkOrder' if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::ITSMChange' if $Name eq 'Kernel::System::ITSMChange';
        return bless {}, 'Local::Cache' if $Name eq 'Kernel::System::Cache';
        die "Unexpected dependency $Name";
    }
}

{
    package Local::Group;
    our %RW = ( 88 => { 6 => 'Change' }, 89 => { 5 => 'Operations' }, 2 => { 99 => 'Admin' } );
    sub GroupGet { return ( ID => $_[2], ValidID => 1 ); }
    sub GroupList { return ( 5 => 'Operations', 6 => 'Change', 7 => 'Other', 99 => 'Admin' ); }
    sub PermissionUserGet {
        my ( $Self, %Param ) = @_;
        return %{ $RW{ $Param{UserID} } || {} };
    }
    sub GroupLookup { return $_[2] eq 'admin' ? 99 : undef; }
}

{
    package Local::WorkOrder;
    our %Data;
    our @UpdateCalls;
    sub WorkOrderGet {
        my ( $Self, %Param ) = @_;
        return $Data{ $Param{WorkOrderID} }
            || { WorkOrderID => $Param{WorkOrderID}, ChangeID => 7, WorkOrderAgentID => 0 };
    }
    sub WorkOrderUpdate {
        my ( $Self, %Param ) = @_;
        push @UpdateCalls, \%Param;
        $Data{ $Param{WorkOrderID} }->{WorkOrderAgentID} = $Param{WorkOrderAgentID};
        return 1;
    }
}

{
    package Local::Config;
    sub Get {
        return [ 5, 6 ] if $_[1] eq 'WorkordersToGroup::AssignableGroups';
        return { Permission => 'rw' } if $_[1] eq 'ITSMWorkOrder::Frontend::AgentITSMWorkOrderAgent';
        return;
    }
}

{
    package Local::User;
    sub GetUserData { return ( UserID => $_[2], ValidID => 1 ); }
}

{
    package Local::ITSMChange;
    sub Permission { return 1; }
}

{
    package Local::Cache;
    sub CleanUp { return 1; }
    sub Delete { return 1; }
}

my $DB = Local::DB->new();
$Kernel::OM = Local::OM->new($DB);
my $Assignment = Kernel::System::WorkordersToGroup::Assignment->new( DBObject => $DB );

my $First = $Assignment->Assign(
    WorkOrderID => 41, GroupID => 5, UserID => 2,
    SourcePackage => 'Test', SourceKey => 'run:1',
);
ok( $First->{Success}, 'new Work Order group assignment is saved' );
is( $First->{Assignment}->{GroupID}, 5, 'group id is stored with the Work Order mapping' );
is( scalar @{ $DB->{Audit} }, 1, 'successful assignment writes one audit record' );

my $Again = $Assignment->Assign( WorkOrderID => 41, GroupID => 5, UserID => 2 );
ok( $Again->{Success} && $Again->{Existing}, 'same assignment is idempotent' );
is( scalar @{ $DB->{Audit} }, 1, 'idempotent retry does not duplicate the audit record' );

my $Conflict = $Assignment->Assign( WorkOrderID => 41, GroupID => 6, UserID => 2 );
ok( !$Conflict->{Success}, 'different group is rejected instead of overwritten' );
is( $Conflict->{Code}, 'ASSIGNMENT_EXISTS_DIFFERENT_GROUP', 'conflict has a stable diagnostic code' );
is( $Assignment->Get( WorkOrderID => 41 )->{GroupID}, 5, 'existing group remains unchanged after conflict' );

$Local::WorkOrder::Data{42} = { WorkOrderID => 42, ChangeID => 7, WorkOrderAgentID => 88 };
my $UnrelatedAgent = $Assignment->Assign( WorkOrderID => 42, GroupID => 5, UserID => 2 );
ok( $UnrelatedAgent->{Success}, 'assignment succeeds when native agent is outside the target group' );
ok( !defined $UnrelatedAgent->{Assignment}->{ClaimedAgentID}, 'agent without target-group write rights is not recorded as claim owner' );
ok( !defined $Local::WorkOrder::Data{42}->{WorkOrderAgentID}, 'native assignment is released when it would disagree with group permissions' );

$Local::WorkOrder::Data{43} = { WorkOrderID => 43, ChangeID => 7, WorkOrderAgentID => 89 };
my $MemberAgent = $Assignment->Assign( WorkOrderID => 43, GroupID => 5, UserID => 2 );
ok( $MemberAgent->{Success}, 'assignment succeeds when native agent belongs to the target group' );
is( $MemberAgent->{Assignment}->{ClaimedAgentID}, 89, 'eligible native agent remains the claim owner' );

my $Deleted = $Assignment->WorkOrderDeleted( WorkOrderID => 43, UserID => 2 );
ok( $Deleted->{Success} && !$Deleted->{Existing}, 'native deletion removes even a claimed mapping' );
ok( !$Assignment->Get( WorkOrderID => 43 ), 'deleted native Work Order leaves no orphan assignment' );

my $DisallowedAssign = $Assignment->Assign( WorkOrderID => 44, GroupID => 7, UserID => 2 );
ok( !$DisallowedAssign->{Success}, 'Assign rejects an active group outside the configured allowlist' );
is( $DisallowedAssign->{Code}, 'GROUP_NOT_ASSIGNABLE', 'disallowed Assign has a stable code' );
my $DisallowedTarget = $Assignment->SetTarget(
    WorkOrderID => 41, TargetType => 'group', TargetID => 7, UserID => 2,
);
is( $DisallowedTarget->{Code}, 'GROUP_NOT_ASSIGNABLE', 'SetTarget rejects an active group outside the allowlist' );
my $DisallowedChange = $Assignment->ChangeGroup( WorkOrderID => 41, GroupID => 7, UserID => 2 );
is( $DisallowedChange->{Code}, 'GROUP_NOT_ASSIGNABLE', 'ChangeGroup rejects an active group outside the allowlist' );

done_testing();
