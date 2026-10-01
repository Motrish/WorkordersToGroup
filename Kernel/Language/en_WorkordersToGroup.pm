# --
# English translations for WorkordersToGroup.
# Copyright (C) 2026 Michael Nehmer | Motrish
# --

package Kernel::Language::en_WorkordersToGroup;

use strict;
use warnings;

sub Data {
    my $Self = shift;
    my %Translation = (
        'Instruction' => 'Instruction',
        'Showing' => 'Showing',
        'of' => 'of',
        'on this page' => 'on this page',
        'Clear filters' => 'Clear filters',
        'Planned Start' => 'Planned start',
        'Planned End' => 'Planned end',
        'Take or assign this ticket' => 'Take or assign this ticket',
        'Take or assign this group Work Order.' => 'Take or assign this group Work Order.',
        'Take Ticket' => 'Take ticket',
        'Assign to a group member' => 'Assign to a group member',
        'No group action is available for this ticket.' => 'No group action is available for this ticket.',
        'Group Work Orders available to claim' => 'Group Work Orders available to claim',
        'Group Work Orders' => 'Group Work Orders',
        'No group Work Orders are available to claim.' => 'No group Work Orders are available to claim.',
        'Loading group Work Orders.' => 'Loading group Work Orders.',
        'The group Work Orders could not be loaded.' => 'The group Work Orders could not be loaded.',
        'All group Work Orders' => 'All group Work Orders',
        'Work Order claimed.' => 'Work Order claimed.',
        'This Work Order has already been claimed or is no longer available.' => 'This Work Order has already been claimed or is no longer available.',
        'This Work Order could not be claimed or is no longer available.' => 'This Work Order could not be claimed or is no longer available.',
        'Agents' => 'Agents',
        'Groups' => 'Groups',
        'Unassigned' => 'Unassigned',
        'Migration progress' => 'Migration progress',
        'Created' => 'Created',
        'Already present' => 'Already present',
        'Failed' => 'Failed',
        'Failure' => 'Failure',
        'Select a valid agent or group.' => 'Select a valid agent or group.',
        'The agent and group list is still loading.' => 'The agent and group list is still loading.',
        'The agent and group list could not be loaded.' => 'The agent and group list could not be loaded.',
        'The current assignment is inactive or no longer available.' => 'The current assignment is inactive or no longer available.',
        'No WorkOrderID is given!' => 'No WorkOrderID is given!',
        'Work Order not found.' => 'Work Order not found.',
        'Change not found for this Work Order.' => 'Change not found for this Work Order.',
        'You need %s permissions on the change!' => 'You need %s permissions on the change!',
        'Assignment was rejected: %s' => 'Assignment was rejected: %s',
        'The selected agent is no longer active.' => 'The selected agent is no longer active.',
        'The selected group no longer exists.' => 'The selected group no longer exists.',
        'The selected group is no longer active.' => 'The selected group is no longer active.',
        'The selected group is not enabled for Work Order assignment.' => 'The selected group is not enabled for Work Order assignment.',
        'Only these active OTOBO group IDs can receive managed Work Orders. Configure at least one group before assigning Work Orders to groups.' => 'Only these active OTOBO group IDs can receive managed Work Orders. Configure at least one group before assigning Work Orders to groups.',
        'No groups are enabled for Work Order assignment. Configure WorkordersToGroup::AssignableGroups in SysConfig.' => 'No groups are enabled for Work Order assignment. Configure WorkordersToGroup::AssignableGroups in SysConfig.',
        'You no longer have permission to assign this Work Order.' => 'You no longer have permission to assign this Work Order.',
        'The saved agent and group assignment no longer match. Choose a new target and save again.' => 'The saved agent and group assignment no longer match. Choose a new target and save again.',
        'The Work Order no longer exists or is no longer available.' => 'The Work Order no longer exists or is no longer available.',
        'The current agent could not be released. The assignment was not changed.' => 'The current agent could not be released. The assignment was not changed.',
        'The Work Order agent could not be updated. The assignment was not changed.' => 'The Work Order agent could not be updated. The assignment was not changed.',
        'The group assignment could not be saved. The assignment was not changed.' => 'The group assignment could not be saved. The assignment was not changed.',
        'The assignment changed while you were editing it. Reload the Work Order and try again.' => 'The assignment changed while you were editing it. Reload the Work Order and try again.',
        'The Work Order target could not be saved. The assignment was not changed.' => 'The Work Order target could not be saved. The assignment was not changed.',
        'The Work Order was not changed.' => 'The Work Order was not changed.',
        'Unsupported request.' => 'Unsupported request.',
        'Previous' => 'Previous',
        'Next' => 'Next',
    );

    # Merge package translations into the already loaded OTOBO catalog.
    $Self->{Translation} ||= {};
    $Self->{Translation}->{$_} = $Translation{$_} for keys %Translation;
    return 1;
}

1;
