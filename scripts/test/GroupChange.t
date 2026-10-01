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
    sub new { bless { AutoCommit => 1 }, $_[0] }
    sub commit { $_[0]->{AutoCommit} = 1; return 1; }
}

{
    package Local::DB;
    sub new {
        my $Self = bless { Rows => {}, Audit => [] }, shift;
        $Self->{dbh} = Local::Handle->new();
        return $Self;
    }
    sub Connect { 1 }
    sub BeginWork { $_[0]->{dbh}->{AutoCommit} = 0; return 1; }
    sub Rollback { $_[0]->{dbh}->{AutoCommit} = 1; return 1; }
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
        if ( $SQL =~ /^UPDATE wotg_assignment SET group_id/ ) {
            my @Value = map { defined $_ ? $$_ : undef } @{ $Param{Bind} };
            my ( $GroupID, $AgentID, undef, $ID, $Version ) = @Value;
            my ($Row) = grep { $_->{ID} == $ID } values %{ $Self->{Rows} };
            return if !$Row || $Row->{Version} != $Version;
            $Row->{GroupID} = $GroupID;
            $Row->{ClaimedAgentID} = $AgentID;
            $Row->{Version}++;
            return 1;
        }
        if ( $SQL =~ /^INSERT INTO wotg_audit/ ) {
            push @{ $Self->{Audit} }, $Param{Bind};
            return 1;
        }
        return 1 if $SQL =~ /SAVEPOINT|RELEASE SAVEPOINT/;
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
        return bless {}, 'Local::User' if $Name eq 'Kernel::System::User';
        return bless {}, 'Local::WorkOrder' if $Name eq 'Kernel::System::ITSMChange::ITSMWorkOrder';
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return bless {}, 'Local::Cache' if $Name eq 'Kernel::System::Cache';
        die "Unexpected dependency $Name";
    }
}

{
    package Local::Group;
    sub GroupGet { return ( ID => $_[2], ValidID => 1 ); }
    sub GroupList { return ( 5 => 'Operations', 6 => 'Change Team', 99 => 'Admin' ); }
    sub GroupLookup { return $_[2] eq 'admin' ? 99 : undef; }
    sub PermissionUserGet {
        my ( $Self, %Param ) = @_;
        return ( 99 => 'Admin' ) if $Param{UserID} == 2;
        return ( 6 => 'Change Team' ) if $Param{UserID} == 31;
        return ( 5 => 'Operations' ) if $Param{UserID} == 32;
        return;
    }
}

{
    package Local::User;
    sub GetUserData { return ( UserID => $_[2], ValidID => 1 ); }
}

{
    package Local::WorkOrder;
    our %Data;
    our @Updates;
    sub WorkOrderGet { return $Data{ $_[2] }; }
    sub WorkOrderUpdate {
        my ( $Self, %Param ) = @_;
        push @Updates, { %Param };
        $Data{ $Param{WorkOrderID} }->{WorkOrderAgentID} = $Param{WorkOrderAgentID};
        return 1;
    }
}

{
    package Local::Config;
    sub Get { return [ 5, 6 ] if $_[1] eq 'WorkordersToGroup::AssignableGroups'; return; }
}

{
    package Local::Cache;
    sub CleanUp { return 1; }
    sub Delete { return 1; }
}

my $DB = Local::DB->new();
$DB->{Rows}->{90} = {
    ID => 1, WorkOrderID => 90, ChangeID => 3, GroupID => 5,
    ClaimedAgentID => 31, SourcePackage => '', SourceKey => '', Version => 1,
};
$DB->{Rows}->{91} = {
    ID => 2, WorkOrderID => 91, ChangeID => 3, GroupID => 5,
    ClaimedAgentID => 32, SourcePackage => '', SourceKey => '', Version => 1,
};
$Local::WorkOrder::Data{90} = { WorkOrderID => 90, ChangeID => 3, WorkOrderAgentID => 31 };
$Local::WorkOrder::Data{91} = { WorkOrderID => 91, ChangeID => 3, WorkOrderAgentID => 32 };
$Kernel::OM = Local::OM->new($DB);
my $Assignment = Kernel::System::WorkordersToGroup::Assignment->new( DBObject => $DB );

my $Keep = $Assignment->ChangeGroup( WorkOrderID => 90, GroupID => 6, UserID => 2 );
ok( $Keep->{Success}, 'group change succeeds without forcing agent release' );
is( $DB->{Rows}->{90}->{ClaimedAgentID}, 31, 'agent who belongs to the new group remains claimed' );
is( $Local::WorkOrder::Data{90}->{WorkOrderAgentID}, 31, 'native Work Order agent stays aligned when retained' );

my $Release = $Assignment->ChangeGroup( WorkOrderID => 91, GroupID => 6, UserID => 2 );
ok( $Release->{Success}, 'group change succeeds when old agent is not in the new group' );
ok( !defined $DB->{Rows}->{91}->{ClaimedAgentID}, 'non-member is removed from the mapping claim' );
ok( !defined $Local::WorkOrder::Data{91}->{WorkOrderAgentID}, 'native agent is released with the mapping claim' );
is( scalar @Local::WorkOrder::Updates, 1, 'native update occurs only for the agent that must be released' );

done_testing();
