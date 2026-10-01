use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::Modules::WorkordersToGroupManagedSaveGuard;

{
    package Kernel;
    our $OM;
}

{
    package Local::Request;
    our %Params;
    sub GetParam { return $Params{ $_[2] }; }
}

{
    package Local::Assignment;
    sub Get { return $_[2] eq '77' ? { WorkOrderID => 77, GroupID => 5 } : undef; }
}

{
    package Local::Layout;
    sub NoPermission { return 'BLOCKED'; }
}

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Request' if $Name eq 'Kernel::System::Web::Request';
        return bless {}, 'Local::Assignment' if $Name eq 'Kernel::System::WorkordersToGroup::Assignment';
        return bless {}, 'Local::Layout' if $Name eq 'Kernel::Output::HTML::Layout';
        die "Unexpected dependency $Name";
    }
}

$Kernel::OM = bless {}, 'Local::OM';
my $Guard = Kernel::Modules::WorkordersToGroupManagedSaveGuard->new(
    Action => 'AgentITSMWorkOrderAgent',
);

%Local::Request::Params = (
    Action => 'AgentITSMWorkOrderAgent', Subaction => 'Save', WorkOrderID => 77,
);
is( $Guard->PreRun(), 'BLOCKED', 'managed Work Order save is rejected on the server before the native controller' );

$Local::Request::Params{WorkOrderID} = 78;
ok( !defined $Guard->PreRun(), 'unmanaged Work Order save continues through native permission checks' );

$Local::Request::Params{Action} = 'AgentWorkordersToGroupTarget';
$Local::Request::Params{WorkOrderID} = 77;
ok( !defined $Guard->PreRun(), 'package-owned target endpoint is not intercepted' );

done_testing();
