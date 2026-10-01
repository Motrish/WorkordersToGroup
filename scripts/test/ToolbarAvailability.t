use strict;
use warnings;
use Test::More;

use lib '.';
use Kernel::Output::HTML::ToolBar::GroupWorkOrders;

{
    package Kernel;
    our $OM;
}

{
    package Local::Language;
    sub new { return bless {}, $_[0]; }
    sub Translate { return $_[1]; }
}

{
    package Local::Layout;
    sub new {
        return bless {
            Baselink       => '/otobo/index.pl?',
            LanguageObject => Local::Language->new(),
        }, $_[0];
    }
}

{
    package Local::Config;
    sub Get { return { AgentWorkordersToGroup => 1 }; }
}

{
    package Local::Group;
    sub PermissionUserGet { return ( 10 => 'Operations' ); }
    sub GroupList { return ( 10 => 'Operations' ); }
}

{
    package Local::Assignment;
    our %CountArgs;
    sub CountUnassigned { my ( $Self, %Param ) = @_; %CountArgs = %Param; die "simulated assignment table failure\n"; }
}

{
    package Local::Log;
    our @Messages;
    sub Log {
        my ( $Self, %Param ) = @_;
        push @Messages, \%Param;
        return 1;
    }
}

{
    package Local::OM;
    sub Get {
        my ( $Self, $Name ) = @_;
        return bless {}, 'Local::Config' if $Name eq 'Kernel::Config';
        return bless {}, 'Local::Group' if $Name eq 'Kernel::System::Group';
        return bless {}, 'Local::Assignment' if $Name eq 'Kernel::System::WorkordersToGroup::Assignment';
        return bless {}, 'Local::Log' if $Name eq 'Kernel::System::Log';
        return Local::Layout->new() if $Name eq 'Kernel::Output::HTML::Layout';
        die "Unexpected dependency $Name";
    }
}

my $WithoutUser = Kernel::Output::HTML::ToolBar::GroupWorkOrders->new();
ok( !defined $WithoutUser->Run(), 'toolbar safely skips contexts without an agent ID' );

$Kernel::OM = bless {}, 'Local::OM';
my $Toolbar = Kernel::Output::HTML::ToolBar::GroupWorkOrders->new( UserID => 7 );
my %Result = $Toolbar->Run( Config => { Priority => 1000650, CssClass => 'WorkordersToGroup', Icon => 'fa fa-users' } );

is( $Result{1000650}->{Count}, 0, 'counter lookup failure leaves a zero badge instead of raising an exception' );
is( $Result{1000650}->{Class}, 'WorkordersToGroup', 'toolbar item remains registered after lookup failure' );
like( $Local::Log::Messages[0]->{Message}, qr/simulated assignment table failure/, 'underlying toolbar failure is logged' );
is( $Local::Assignment::CountArgs{UserID}, 7, 'toolbar scopes the count cache to the current user' );

done_testing();
