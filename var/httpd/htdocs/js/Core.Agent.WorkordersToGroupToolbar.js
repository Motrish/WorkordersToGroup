/* Mark the native group Work Order link when claimable orders are available. */
(function () {
    'use strict';

    function Start() {
        const Item = document.querySelector('#ToolBar .WorkordersToGroup');
        if (!Item) {
            return;
        }
        const Counter = Item.querySelector('.Counter');
        const Icon = Item.matches('i.fa.fa-users') ? Item : Item.querySelector('i.fa.fa-users');
        if (!Icon) {
            return;
        }
        const Count = Number.parseInt(String(Counter?.textContent || '').trim(), 10);
        Icon.classList.toggle('HasAvailableWorkOrders', Number.isFinite(Count) && Count > 0);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Start, { once: true });
    }
    else {
        Start();
    }
}());
