use strict;
use warnings;
use Test::More;
use JSON::PP qw(decode_json);
use FindBin;

{
    package Kernel;
    our $OM;
}
package main;
our %MockObjects;
our $UserListArgs;
our $ConfigGetArgs;

require "$FindBin::Bin/../../Kernel/Modules/AgentWorkordersToGroupTarget.pm";

{
    package Local::User;
    sub UserList {
        my ( $Self, %Param ) = @_;
        $main::UserListArgs = \%Param;
        return ( 17 => 'Abwesender Agent', 42 => 'Verfügbarer Agent' );
    }
}

{
    package Local::Group;
    sub GroupList { return ( 8 => 'Infrastruktur', 9 => 'Service Desk' ); }
}

{
    package Local::Assignment;
    sub Get { return; }
    sub AssignableGroupIDs { return [ 8 ]; }
}

{
    package Local::Config;
    sub Get {
        my ( $Self, $Key ) = @_;
        $main::ConfigGetArgs = $Key;
        return { Permission => 'rw' };
    }
}

{
    package Local::Request;
    sub GetParam {
        my ( $Self, %Param ) = @_;
        return 123 if $Param{Param} eq 'WorkOrderID';
        return 'Options' if $Param{Param} eq 'Subaction';
        return;
    }
}

{
    package Local::WorkOrder;
    sub WorkOrderGet { return { WorkOrderID => 123, ChangeID => 55, WorkOrderAgentID => 42 }; }
}

{
    package Local::ITSMChange;
    sub ChangeGet { return { ChangeID => 55 }; }
    sub Permission { return 1; }
}

{
    package Local::Language;
    sub Translate { return $_[1]; }
}

{
    package Local::Layout;
    sub JSONEncode { my ( $Self, %Param ) = @_; return JSON::PP::encode_json( $Param{Data} ); }
    sub Attachment { my ( $Self, %Param ) = @_; return \%Param; }
}

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return $main::MockObjects{$Name} if exists $main::MockObjects{$Name};
        die "Unexpected dependency $Name";
    }
}

$Kernel::OM = bless {}, 'Local::OM';
$MockObjects{'Kernel::System::User'} = bless {}, 'Local::User';
$MockObjects{'Kernel::System::Group'} = bless {}, 'Local::Group';
$MockObjects{'Kernel::Config'} = bless {}, 'Local::Config';
$MockObjects{'Kernel::System::Web::Request'} = bless {}, 'Local::Request';
$MockObjects{'Kernel::System::ITSMChange::ITSMWorkOrder'} = bless {}, 'Local::WorkOrder';
$MockObjects{'Kernel::System::ITSMChange'} = bless {}, 'Local::ITSMChange';
$MockObjects{'Kernel::System::WorkordersToGroup::Assignment'} = bless {}, 'Local::Assignment';
$MockObjects{'Kernel::Output::HTML::Layout'} = bless {
    LanguageObject => bless( {}, 'Local::Language' ),
    UserChallengeToken => 'token',
    Charset => 'utf-8',
}, 'Local::Layout';

my $Controller = bless {}, 'Kernel::Modules::AgentWorkordersToGroupTarget';
my $EndpointResponse = $Controller->Run( UserID => 7 );
my $EndpointData = decode_json( $EndpointResponse->{Content} );
is( $ConfigGetArgs, 'ITSMWorkOrder::Frontend::AgentITSMWorkOrderAgent', 'options endpoint loads native permission settings from Kernel::Config' );
is( $EndpointData->{Success}, 1, 'options endpoint returns successfully after resolving native permission settings' );

my $Response = $Controller->_Options(
    WorkOrderID => 123,
    WorkOrder   => { WorkOrderAgentID => 42 },
);
my $Data = decode_json( $Response->{Content} );

is( $UserListArgs->{Type}, 'Long', 'agent list uses long display names' );
is( $UserListArgs->{Valid}, 1, 'agent list contains active agents' );
ok( !exists $UserListArgs->{NoOutOfOffice}, 'out-of-office agents are not removed from assignments' );
is_deeply( [ map { $_->{ID} } @{ $Data->{UserOptions} } ], [ 17, 42 ], 'all active agents are present' );
is( $Data->{CurrentTarget}, 'user:42', 'existing direct agent is preselected' );
is_deeply( [ map { $_->{ID} } @{ $Data->{GroupOptions} } ], [ 8 ], 'only explicitly assignable active groups are present' );
like( $Data->{NoAssignableGroupsLabel}, qr/AssignableGroups/, 'selector explains the allowlist setting when no group is available' );

done_testing();
