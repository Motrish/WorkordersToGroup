use strict;
use warnings;
use Test::More;
use FindBin;

my @Templates = qw(
    Kernel/Output/HTML/Templates/Standard/AdminWorkordersToGroup.tt
    Kernel/Output/HTML/Templates/Standard/AgentWorkordersToGroup.tt
    Kernel/Output/HTML/Templates/Standard/AgentWorkordersToGroupManage.tt
);

for my $Template (@Templates) {
    my $Path = "$FindBin::Bin/../../$Template";
    open my $File, '<', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Source = <$File>;
    close $File;

    my @Stack;
    my @Errors;
    while ( $Source =~ /\[\%\s*(.*?)\s*\%\]/sg ) {
        my $Directive = $1;
        if ( $Directive =~ /\A(IF|UNLESS|FOREACH)\b/ ) {
            push @Stack, $1;
        }
        elsif ( $Directive =~ /\AELSE\b/ ) {
            push @Errors, 'ELSE is only valid inside IF or UNLESS'
                if !@Stack || $Stack[-1] !~ /\A(?:IF|UNLESS)\z/;
        }
        elsif ( $Directive =~ /\AEND\b/ ) {
            push @Errors, 'END has no matching control block' if !@Stack;
            pop @Stack if @Stack;
        }
    }
    push @Errors, 'control block is not closed' if @Stack;
    is_deeply( \@Errors, [], "$Template has valid IF/FOREACH control flow" );
    my $ExpectedBlock = $Template =~ /Manage/ ? 'Manage' : 'Overview';
    like( $Source, qr/RenderBlockStart\("$ExpectedBlock"\)/, "$Template uses the expected render block" );
}

my $OverviewPath = "$FindBin::Bin/../../Kernel/Output/HTML/Templates/Standard/AgentWorkordersToGroup.tt";
open my $OverviewFile, '<', $OverviewPath or die "Cannot read $OverviewPath: $!";
my $Overview = do { local $/; <$OverviewFile> };
close $OverviewFile;
like( $Overview, qr/WorkOrder\.ChangeNumber[\s\S]*?WorkOrder\.ChangeTitle/, 'team overview renders change number and title' );
like( $Overview, qr/WorkOrder\.InstructionExcerpt[\s\S]*?WorkOrder\.PlannedStartTime[\s\S]*?WorkOrder\.PlannedEndTime/, 'team overview renders instruction excerpt and planned dates' );
like( $Overview, qr/class="[^"]*WorkordersToGroupList"[\s\S]*?data-sort-column="3"[\s\S]*?data-filter-column="3"/, 'team overview includes independent sortable and filterable columns' );
like( $Overview, qr/class="WorkordersToGroupColumnHeader"><button[^>]*data-sort-column="3"[\s\S]*?<\/button><button[^>]*class="WorkordersToGroupFilterToggle"[^>]*aria-expanded="false"[\s\S]*?<\/button><input id="WorkordersToGroupFilter3"[^>]*data-filter-column="3"[^>]*hidden/, 'sort control and hidden live filter share a compact header line' );
is( scalar(() = $Overview =~ /class="WorkordersToGroupFilterToggle"/g), 8, 'every sortable data column has a magnifier filter control' );
unlike( $Overview, qr/WorkordersToGroupFilterRow/, 'team overview has no separate filter header row' );
like( $Overview, qr/class="WorkordersToGroupClearFilters WorkordersToGroupPillButton"/, 'clear-filter control uses the compact button class' );
like( $Overview, qr/<button type="submit" class="WorkordersToGroupPillButton">/, 'claim submit uses the compact button class' );
like( $Overview, qr/WorkOrder\.WorkOrderTitle[\s\S]*?<\/td>\s*<td><div class="WorkordersToGroupInstruction">/, 'work order title and instruction are rendered in separate table cells' );

my $ZoomPopupPath = "$FindBin::Bin/../../Kernel/Output/HTML/Templates/Standard/AgentWorkordersToGroupManage.tt";
open my $ZoomPopupFile, '<', $ZoomPopupPath or die "Cannot read $ZoomPopupPath: $!";
my $ZoomPopup = do { local $/; <$ZoomPopupFile> };
close $ZoomPopupFile;
like( $ZoomPopup, qr/name="ChallengeToken"/, 'work order action popup submits the CSRF challenge token' );
like( $ZoomPopup, qr/name="TargetUserID"/, 'manager popup exposes a group member selector' );

done_testing();
