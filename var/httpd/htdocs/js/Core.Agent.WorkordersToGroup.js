/* WorkordersToGroup enhancement for the native AgentITSMWorkOrderAgent popup. */
(function () {
    'use strict';

    function Start() {
        const Form = document.querySelector('form[name="compose"]');
        if (!Form) {
            return;
        }

        // OTOBO commonly separates query parameters with semicolons. Read the
        // native hidden fields first and normalize the URL for older templates.
        const Query = new URLSearchParams(window.location.search.replace(/;/g, '&'));
        const NativeAction = Form.querySelector('input[name="Action"]');
        const Action = NativeAction?.value || Query.get('Action')?.split(';')[0];
        if (Action !== 'AgentITSMWorkOrderAgent') {
            return;
        }

        const UserInput = document.getElementById('User');
        const UserSelected = document.getElementById('UserSelected');
        if (!UserInput || !UserSelected) {
            return;
        }

        const WorkOrderID = Form.querySelector('[name="WorkOrderID"]')?.value || Query.get('WorkOrderID');
        const Field = UserInput.closest('.Field');
        const Label = document.querySelector('label[for="User"]');
        const ErrorMessage = document.getElementById('UserServerError');
        if (!WorkOrderID || !Field) {
            return;
        }

        const Select = document.createElement('select');
        Select.id = 'WorkordersToGroupTarget';
        Select.name = 'Target';
        Select.className = 'W75pc';
        Select.setAttribute('aria-describedby', 'WorkordersToGroupTargetError');
        if (Label) {
            Label.htmlFor = Select.id;
        }
        Field.replaceChildren(Select);
        UserInput.remove();
        UserSelected.remove();

        const Error = document.createElement('div');
        Error.id = 'WorkordersToGroupTargetError';
        Error.className = 'TooltipErrorMessage';
        Error.setAttribute('role', 'alert');
        Error.hidden = true;
        Field.appendChild(Error);

        let Ready = false;
        let Messages = {
            Loading: 'The agent and group list is still loading.',
            LoadError: 'The agent and group list could not be loaded.',
            InvalidCurrent: 'The current assignment is inactive or no longer available.',
            InvalidTarget: 'Select a valid agent or group.'
        };
        const ShowError = function (Message) {
            Error.textContent = Message || Messages.LoadError;
            Error.hidden = false;
            Select.classList.add('ServerError');
        };
        Select.addEventListener('change', function () {
            Error.hidden = true;
            Select.classList.remove('ServerError');
        });

        const NativeSubaction = Form.querySelector('input[name="Subaction"]');
        const Challenge = Form.querySelector('input[name="ChallengeToken"]') || document.createElement('input');
        Challenge.type = 'hidden';
        Challenge.name = 'ChallengeToken';
        if (!Challenge.parentNode) {
            Form.appendChild(Challenge);
        }

        Form.addEventListener('submit', function (Event) {
            if (!Ready) {
                Event.preventDefault();
                ShowError(Messages.Loading);
                return;
            }
            if (!Select.value || Select.selectedOptions[0]?.disabled) {
                Event.preventDefault();
                ShowError(Messages.InvalidTarget);
                Select.focus();
                return;
            }
            if (NativeAction) {
                NativeAction.value = 'AgentWorkordersToGroupTarget';
            }
            if (NativeSubaction) {
                NativeSubaction.value = 'Save';
            }
        });

        const ActionURL = new URL(Form.action, window.location.href);
        ActionURL.search = '';
        ActionURL.searchParams.set('Action', 'AgentWorkordersToGroupTarget');
        ActionURL.searchParams.set('Subaction', 'Options');
        ActionURL.searchParams.set('WorkOrderID', WorkOrderID);

        fetch(ActionURL.toString(), {
            credentials: 'same-origin',
            cache: 'no-store',
            headers: { Accept: 'application/json' }
        }).then(function (Response) {
            if (!Response.ok) {
                throw new Error('HTTP ' + Response.status);
            }
            return Response.json();
        }).then(function (Data) {
            if (!Data || !Data.Success) {
                throw new Error('Die Liste wurde nicht freigegeben.');
            }
            Messages = {
                Loading: Data.LoadingLabel,
                LoadError: Data.ListErrorLabel,
                InvalidCurrent: Data.InvalidCurrentLabel,
                InvalidTarget: Data.InvalidTargetLabel
            };

            const NoneOption = document.createElement('option');
            NoneOption.value = 'none';
            NoneOption.textContent = Data.NoneLabel;
            Select.appendChild(NoneOption);

            const AddGroup = function (LabelText, Prefix, Entries) {
                const Group = document.createElement('optgroup');
                Group.label = LabelText;
                (Entries || []).forEach(function (Entry) {
                    const Option = document.createElement('option');
                    Option.value = Prefix + ':' + Entry.ID;
                    Option.textContent = Entry.Name;
                    Group.appendChild(Option);
                });
                if (Prefix === 'group' && (!Entries || !Entries.length)) {
                    const EmptyOption = document.createElement('option');
                    EmptyOption.value = '';
                    EmptyOption.disabled = true;
                    EmptyOption.textContent = Data.NoAssignableGroupsLabel;
                    Group.appendChild(EmptyOption);
                }
                Select.appendChild(Group);
            };
            AddGroup(Data.UsersLabel, 'user', Data.UserOptions);
            AddGroup(Data.GroupsLabel, 'group', Data.GroupOptions);

            const CurrentTarget = Data.CurrentTarget || 'none';
            const HasCurrentTarget = Array.from(Select.options).some(function (Option) {
                return Option.value === CurrentTarget;
            });
            if (!HasCurrentTarget) {
                const InvalidOption = document.createElement('option');
                InvalidOption.value = CurrentTarget;
                InvalidOption.textContent = Messages.InvalidCurrent;
                InvalidOption.disabled = true;
                Select.insertBefore(InvalidOption, Select.options[1] || null);
            }
            Select.value = CurrentTarget;
            Challenge.value = Data.ChallengeToken || '';
            Ready = true;
            if (!HasCurrentTarget) {
                ShowError(Messages.InvalidCurrent);
            }
        }).catch(function (Failure) {
            ShowError(Failure.message);
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Start, { once: true });
    }
    else {
        Start();
    }
}());
