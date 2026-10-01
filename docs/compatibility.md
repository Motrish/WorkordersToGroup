# Compatibility and verification record

## Declared target

- OTOBO 11.0.13 in the 11.0 series.
- ITSMChangeManagement 11.0.3 or compatible 11.0.3+ package API.
- Consumer integration: `CustomChangeAutomation 0.3.7` requires `WorkordersToGroup 0.2.0` or later.

## Release source examined

- OTOBO repository tag `rel-11_0_13`, resolving in the inspected checkout to commit `d2e60ccf95709928aeb8c8de1ea406122c8aa99f`.
- ITSMChangeManagement package `11.0.3`, extracted from its official OPM.
- The native `AgentITSMWorkOrderAgent` controller reads `User`/`UserSelected`, checks the configured native Change permission, then calls `WorkOrderUpdate(WorkOrderID, WorkOrderAgentID, UserID)`. Its template has one user-search input and a hidden selected-user field. WorkordersToGroup replaces those controls in the rendered popup and routes saves through a server-side endpoint that repeats the native permission check. A `PreApplicationModule` blocks direct native `Subaction=Save` requests for managed Work Orders; unmanaged Work Orders still use the configured native permission modules.
- ITSM `WorkOrderUpdate` explicitly accepts `undef` to clear `WorkOrderAgentID`; the setter only passes the fields it intends to change.
- OTOBO's native agent toolbar module renders a configurable icon and counter. WorkordersToGroup registers there and adds package-owned JavaScript/CSS so the icon navigates directly to the team overview; it blinks when claimable group orders are available. There is no separate quick-list button.
- The ITSM Work Order zoom menu loads configured output modules. WorkordersToGroup adds a group-aware action that displays a CSRF-protected claim form to eligible agents and a member selector to Change Managers/admins.
- `UserList(Type => 'Long', Valid => 1)` and `GroupList(Valid => 1)` provide all active-agent and active-group dropdown choices, including agents currently marked out of office. Group visibility/claim counts use OTOBO's effective group permissions, including role-derived membership.
- ITSM's state machine uses `next_state_id = 0` for end states. The count and claim-list query excludes those states, as well as native-assigned orders.
- The assignment service locks both the mapping and native Work Order row before mutation, then validates version/readback. Native Work Order listeners are temporarily queued and delivered after the package transaction commits; an outer caller-owned transaction is rejected for native updates because OTOBO exposes no commit hook to this service.
- The `WorkOrderDeletePost` listener removes the package mapping and retains an audit entry; Admin removal also supports a pre-existing orphan row. The 0.2.13 upgrade removes the obsolete stylesheet left by packages that installed it outside the Agent skin path.
- The overview's main pages use `(change_time, id)` keyset cursors and filter native Work Order existence before limiting results. Numeric `Start` remains only as a compatibility path for older URLs.
- Table column filters render inline beside their magnifier controls, so opening one does not overlay the first data row.

These are source-level checks against the declared releases; they do not prove behavior in a target instance with local SysConfig or permission customizations.

## Verification performed in the workspace

- Perl syntax checks pass for all 15 plugin Perl modules.
- JavaScript syntax checks pass for all 3 plugin JavaScript files.
- SOPM and SysConfig XML parse; the fallback OPM builder succeeds, and all 23 manifest files match their embedded package bytes.
- The local suite passes 18 test files and 230 assertions, covering assignment persistence/idempotence, race checks, permission chains, native-save guards, post-commit events, rollback cleanup, orphan cleanup, cursor pagination, large source reads, translation merging, terminal-state rejection, and audit creation.
- The CustomChangeAutomation 0.3.7 test suite checks the WorkordersToGroup dependency and that its duplicate permission registrations and legacy menu are disabled.
- Source archive validation confirms all 46 files match the source tree. The embedded CodeUpgrade passes Perl syntax validation. No Package Manager install, database migration, OTOBO browser render, or native two-agent race test ran because no initialized OTOBO database/application is available here.

## Required target-instance checks

1. Install OTOBO 11.0.13 and ITSMChangeManagement 11.0.3 in a disposable instance; install WorkordersToGroup 1.0.0, rebuild SysConfig/cache, then visit the native assignment popup as Change Builder and Change Manager.
2. Verify the popup has no user-search field; it has all active agents and groups, prefills an existing target, supports keyboard selection, and shows useful errors for invalid/inactive targets and permission denial.
3. Assign direct agent, group, group-to-group, and group-to-agent; verify native `WorkOrderAgentID`, the single mapping row, and audit history remain consistent after both successful writes and injected failures.
4. Check the toolbar at zero and with many assignments. Confirm the users icon blinks red when an unassigned Work Order belongs to an RW group of the agent, opens the team overview directly, and has no separate quick-list button. Test effective RW membership through roles, read-only membership, non-members, inactive groups, closed orders, and already assigned orders. Confirm the exact badge count and successful claim behavior.
5. In Work Order zoom, verify the claim action is shown only for eligible group members and the member selector only for Change Managers/admins. Submit a valid claim/reassignment and invalid-CSRF requests. Try the native Save URL directly for a managed Work Order; it must be blocked while unmanaged orders still use OTOBO's active permission chain. Race two agents for one order; exactly one claim must succeed and the losing request must show a conflict.
6. Upgrade a 0.3.6 Change Automation installation: run migration preview/apply, confirm its old permission settings and team menu are inactive, the route only redirects, and new worker-created Work Orders still register their slot group through the public Assignment API.
7. Test native Work Order deletion with claimed and unclaimed mappings and verify the mapping disappears while `WORKORDER_DELETED` remains in audit. Upgrade from 0.2.4, 0.2.5, and 0.2.12 on each supported database backend; verify the composite index is present exactly once.
8. Test package uninstall with active mappings. Package removal retains data tables, so enforcement must not be removed while managed assignments remain active.

The local package and test checks do not replace these target-instance integration checks; no initialized OTOBO database or browser instance was available in this workspace.
