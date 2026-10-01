use strict;
use warnings;
use Test::More;
use JSON::PP qw(decode_json);

use lib '.';
use Kernel::Modules::AgentWorkordersToGroupTake;

{
    package Kernel;
    our $OM;
}

{
    package Local::Request;
    sub new { bless { Params => $_[1] }, $_[0] }
    sub GetParam { return $_[0]->{Params}->{ $_[2] }; }
}

{
    package Local::Layout;
    sub new { bless { Charset => 'utf-8' }, $_[0] }
    sub ChallengeTokenCheck { die 'invalid IDs must not reach CSRF or claim handling'; }
    sub JSONEncode { return JSON::PP::encode_json( $_[2] ); }
    sub Attachment { my ( $Self, %Param ) = @_; return \%Param; }
    sub Redirect { my ( $Self, %Param ) = @_; return $Param{OP}; }
}

{
    package Local::Log;
    our @Messages;
    sub Log { my ( $Self, %Param ) = @_; push @Messages, $Param{Message}; return 1; }
}

{
    package Local::OM;
    sub new { bless { Params => $_[1] }, $_[0] }
    sub Get {
        my ( $Self, $Name ) = @_;
        return Local::Request->new( $Self->{Params} ) if $Name eq 'Kernel::System::Web::Request';
        return Local::Layout->new() if $Name eq 'Kernel::Output::HTML::Layout';
        return bless {}, 'Local::Log' if $Name eq 'Kernel::System::Log';
        die "Unexpected dependency $Name";
    }
}

for my $Case (
    { Name => 'missing ID', Params => { Ajax => 1 } },
    { Name => 'empty ID', Params => { WorkOrderID => '', Ajax => 1 } },
    { Name => 'non-numeric ID', Params => { WorkOrderID => '9x', Ajax => 1 } },
) {
    $Kernel::OM = Local::OM->new( $Case->{Params} );
    my $Controller = Kernel::Modules::AgentWorkordersToGroupTake->new( UserID => 7 );
    my $Response = $Controller->Run();
    is( decode_json( $Response->{Content} )->{Code}, 'INPUT_INVALID', "$Case->{Name} Ajax request returns a safe code" );
    is( decode_json( $Response->{Content} )->{Success}, 0, "$Case->{Name} Ajax request is rejected" );
}

for my $Case (
    { Name => 'missing ID', Params => {} },
    { Name => 'empty ID', Params => { WorkOrderID => '' } },
    { Name => 'non-numeric ID', Params => { WorkOrderID => 'x' } },
) {
    $Kernel::OM = Local::OM->new( $Case->{Params} );
    my $Controller = Kernel::Modules::AgentWorkordersToGroupTake->new( UserID => 7 );
    is( $Controller->Run(), 'Action=AgentWorkordersToGroup;Filter=unassigned;ClaimError=1', "$Case->{Name} POST redirects safely" );
}

like( $Local::Log::Messages[-1], qr/INPUT_INVALID\z/, 'normal POST logs the stable input error code' );

done_testing();
