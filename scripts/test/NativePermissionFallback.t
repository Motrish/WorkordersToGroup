use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck;

{
    package Kernel;
    our $OM;
}

{
    package Local::Config;
    our $Registry;
    sub Get { return $Registry if $_[1] eq 'ITSMWorkOrder::TakePermission'; return; }
}

{
    package Local::Main;
    sub Require { return 1; }
}

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return bless {}, 'Local::Main' if $Name eq 'Kernel::System::Main';
        die "Unexpected dependency $Name";
    }
}

{
    package Local::Grant;
    our $Calls = 0;
    sub new { bless {}, $_[0] }
    sub Run { $Calls++; return 1; }
}

{
    package Local::Deny;
    our $Calls = 0;
    sub new { bless {}, $_[0] }
    sub Run { $Calls++; return; }
}

$Kernel::OM = bless {}, 'Local::OM';
my $Check = Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck->new();
my %Context = ( PermissionRegistry => 'ITSMWorkOrder::TakePermission', Type => 'rw', UserID => 4, WorkOrderID => 19 );

$Local::Config::Registry = {
    '00-WorkordersToGroup' => {
        Module => 'Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck',
        Granted => 1, Required => 1,
    },
    '10-SiteNativeGrant' => { Module => 'Local::Grant', Granted => 1, Required => 0 },
};
ok( $Check->_NativePermissions(%Context), 'fallback uses the active native module registry' );
is( $Local::Grant::Calls, 1, 'active configured native module is invoked' );

$Local::Grant::Calls = 0;
$Local::Deny::Calls = 0;
$Local::Config::Registry = {
    '00-WorkordersToGroup' => {
        Module => 'Kernel::System::ITSMChange::ITSMWorkOrder::Permission::WorkordersToGroupCheck',
        Granted => 1, Required => 1,
    },
    '10-RequiredNativeDeny' => { Module => 'Local::Deny', Granted => 0, Required => 1 },
    '20-LaterGrant' => { Module => 'Local::Grant', Granted => 1, Required => 0 },
};
ok( !$Check->_NativePermissions(%Context), 'Required native denial is preserved' );
is( $Local::Deny::Calls, 1, 'required native check runs' );
is( $Local::Grant::Calls, 0, 'later grant does not bypass a required native denial' );

done_testing();
