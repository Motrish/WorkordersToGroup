/* Sortable and filterable columns in the team Work Order overview. */
(function () {
    'use strict';

    function Start() {
        document.querySelectorAll('table.WorkordersToGroupList').forEach(EnhanceTable);
    }

    function EnhanceTable(Table) {
        const Body = Table.tBodies[0];
        if (!Body) {
            return;
        }

        const Rows = Array.from(Body.querySelectorAll('tr[data-workorder-row]'));
        const OriginalOrder = new Map(Rows.map(function (Row, Index) { return [Row, Index]; }));
        const Filters = Array.from(Table.querySelectorAll('input[data-filter-column]'));
        const FilterToggles = Array.from(Table.querySelectorAll('button[data-filter-toggle]'));
        const FilterByID = new Map(Filters.map(function (Input) { return [Input.id, Input]; }));
        const Content = Table.closest('.Content');
        const Status = Content?.querySelector('.WorkordersToGroupTableStatus');
        const ClearButton = Content?.querySelector('.WorkordersToGroupClearFilters');

        function SetFilterOpen(Input, Open) {
            const Toggle = Table.querySelector('button[aria-controls="' + Input.id + '"]');
            Input.hidden = !Open;
            Toggle?.setAttribute('aria-expanded', Open ? 'true' : 'false');
            Toggle?.closest('th')?.classList.toggle('WorkordersToGroupFilterOpen', Open);
        }

        function UpdateFilters() {
            const ActiveFilters = Filters.map(function (Input) {
                return {
                    Column: Number(Input.dataset.filterColumn),
                    Value: Input.value.trim().toLocaleLowerCase()
                };
            }).filter(function (Filter) { return Filter.Value; });

            let VisibleCount = 0;
            Rows.forEach(function (Row) {
                const Matches = ActiveFilters.every(function (Filter) {
                    const Cell = Row.cells[Filter.Column];
                    const Value = Cell ? (Cell.dataset.sortValue || Cell.textContent).trim().toLocaleLowerCase() : '';
                    return Value.includes(Filter.Value);
                });
                Row.style.display = Matches ? '' : 'none';
                if (Matches) {
                    VisibleCount++;
                }
            });

            if (Status) {
                Status.textContent = [
                    Status.dataset.showing || 'Showing',
                    VisibleCount,
                    Status.dataset.of || 'of',
                    Rows.length,
                    Status.dataset.onPage || 'on this page'
                ].join(' ');
            }
        }

        Table.querySelectorAll('button[data-sort-column]').forEach(function (Button) {
            Button.addEventListener('click', function () {
                const Column = Number(Button.dataset.sortColumn);
                const Header = Button.closest('th');
                const CurrentSort = Header?.getAttribute('aria-sort');
                const Direction = CurrentSort === 'ascending' ? -1 : 1;

                Table.querySelectorAll('th[aria-sort]').forEach(function (Cell) {
                    Cell.setAttribute('aria-sort', 'none');
                    const Indicator = Cell.querySelector('.WorkordersToGroupSortIndicator');
                    if (Indicator) {
                        Indicator.textContent = '↕';
                    }
                });

                if (Header) {
                    Header.setAttribute('aria-sort', Direction === 1 ? 'ascending' : 'descending');
                    const Indicator = Button.querySelector('.WorkordersToGroupSortIndicator');
                    if (Indicator) {
                        Indicator.textContent = Direction === 1 ? '▲' : '▼';
                    }
                }

                Rows.sort(function (RowA, RowB) {
                    const CellA = RowA.cells[Column];
                    const CellB = RowB.cells[Column];
                    const ValueA = CellA ? (CellA.dataset.sortValue || CellA.textContent).trim() : '';
                    const ValueB = CellB ? (CellB.dataset.sortValue || CellB.textContent).trim() : '';
                    const Comparison = ValueA.localeCompare(ValueB, undefined, { numeric: true, sensitivity: 'base' });
                    return Comparison ? Comparison * Direction : OriginalOrder.get(RowA) - OriginalOrder.get(RowB);
                });

                Rows.forEach(function (Row) { Body.appendChild(Row); });
                UpdateFilters();
            });
        });

        FilterToggles.forEach(function (Toggle) {
            Toggle.addEventListener('click', function () {
                const Input = FilterByID.get(Toggle.getAttribute('aria-controls'));
                if (!Input) {
                    return;
                }
                if (Input.hidden) {
                    SetFilterOpen(Input, true);
                    Input.focus();
                }
                else if (!Input.value.trim()) {
                    SetFilterOpen(Input, false);
                }
                else {
                    Input.focus();
                }
            });
        });

        Filters.forEach(function (Input) {
            Input.addEventListener('input', function () {
                if (Input.value.trim()) {
                    SetFilterOpen(Input, true);
                }
                UpdateFilters();
            });
            Input.addEventListener('blur', function () {
                window.setTimeout(function () {
                    if (!Input.value.trim()) {
                        SetFilterOpen(Input, false);
                    }
                }, 0);
            });
        });
        ClearButton?.addEventListener('click', function () {
            Filters.forEach(function (Input) { Input.value = ''; });
            Filters.forEach(function (Input) { SetFilterOpen(Input, false); });
            UpdateFilters();
        });
        UpdateFilters();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Start, { once: true });
    }
    else {
        Start();
    }
}());
