import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';
import { setGlobal, withGlobal } from '../../../global';

import { INITIAL_STATE } from '../../../global/initialState';
import { selectCurrentAccountId } from '../../../global/selectors';
import { cloneDeep } from '../../../util/iteratees';
import { pause } from '../../../util/schedulers';
import { getIsMainActive } from './getIsMainActive';

import Transition from '../../ui/Transition';

const ACCOUNT_A = '0-mainnet';
const ACCOUNT_B = '1-mainnet';

// TeactN flushes container updates on a microtask, Teact re-renders on rAF
const flushUpdates = () => pause(50);

// Stands in for `Main` and prints the account its container has mapped
const MainProbe = withGlobal<{ accountId?: string }>(
  (global) => ({ shownAccountId: selectCurrentAccountId(global) }),
  getIsMainActive,
)(({ shownAccountId }: { shownAccountId?: string }) => <div className="probe">{shownAccountId}</div>);

let root: HTMLDivElement;

beforeEach(() => {
  root = document.createElement('div');
  document.body.appendChild(root);
  setCurrentAccount(ACCOUNT_A);
});

afterEach(() => {
  TeactDOM.render(undefined, root);
  root.remove();
});

// Renders `Main` the way `App` does
function renderApp(mainKey: number, accountId: string) {
  TeactDOM.render(
    <Transition name="semiFade" activeKey={mainKey} shouldCleanup>
      <MainProbe key={mainKey} accountId={accountId} />
    </Transition>,
    root,
  );
}

function setCurrentAccount(accountId: string) {
  setGlobal({ ...cloneDeep(INITIAL_STATE), currentAccountId: accountId });
}

// The containers get the new account before `App` re-renders and starts the transition. TeactN defers
// container updates while a transition runs, so the order matters.
async function switchCurrentAccount(accountId: string) {
  setCurrentAccount(accountId);
  await pause(0);
}

function getShownAccounts() {
  return Array.from(root.querySelectorAll('.probe')).map((element) => element.textContent);
}

it('keeps the previous account in the outgoing Main while the new one fades in', async () => {
  renderApp(1, ACCOUNT_A);
  await flushUpdates();

  await switchCurrentAccount(ACCOUNT_B);
  renderApp(2, ACCOUNT_B);
  await flushUpdates();

  expect(getShownAccounts()).toEqual([ACCOUNT_A, ACCOUNT_B]);
});

it('switches the same Main to the new account when it is kept for the landscape Agent', async () => {
  renderApp(1, ACCOUNT_A);
  await flushUpdates();

  await switchCurrentAccount(ACCOUNT_B);
  renderApp(1, ACCOUNT_B);
  await flushUpdates();

  expect(getShownAccounts()).toEqual([ACCOUNT_B]);
});
