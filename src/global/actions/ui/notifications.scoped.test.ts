import './notifications';
import '../api/notifications';

import type { GlobalState } from '../../types';

import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { selectNotificationAddressesSlow } from '../../selectors/notifications';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(),
}));
jest.mock('../../selectors', () => ({ selectAccounts: jest.fn() }));
jest.mock('../../selectors/notifications', () => ({ selectNotificationAddressesSlow: jest.fn() }));

const REMOVED = '0-ton-mainnet';
const SURVIVOR = '0-ton-testnet';
const ADDED_DURING_REQUEST = '1-ton-testnet';

type Handler = (
  global: GlobalState,
  actions: AnyLiteral,
  payload?: { accountIds: string[] },
) => Promise<void>;

const deleteAllHandler = jest.mocked(addActionHandler).mock.calls
  .find(([action]) => action === 'deleteAllNotificationAccounts')![1] as Handler;
const toggleHandler = jest.mocked(addActionHandler).mock.calls
  .find(([action]) => action === 'toggleNotifications')![1] as Handler;

function makeGlobal(enabledAccounts: string[]) {
  return {
    pushNotifications: {
      enabledAccounts,
      userToken: 'user-token',
      platform: 'ios',
      isAvailable: true,
    },
    settings: { langCode: 'en' },
  } as unknown as GlobalState;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(setGlobal).mockImplementation((global) => jest.mocked(getGlobal).mockReturnValue(global));
  jest.mocked(selectNotificationAddressesSlow).mockImplementation((_global, accountIds) => (
    Object.fromEntries(accountIds.map((accountId) => [accountId, [{ address: `${accountId}-address` }]]))
  ) as ReturnType<typeof selectNotificationAddressesSlow>);
});

it('removes only the captured network accounts after delayed unsubscribe', async () => {
  const pending = deferred<{ ok: true }>();
  jest.mocked(callApi).mockReturnValue(pending.promise);
  const initial = makeGlobal([REMOVED, SURVIVOR]);
  jest.mocked(getGlobal).mockReturnValue(initial);

  const result = deleteAllHandler(initial, {}, { accountIds: [REMOVED] });
  await Promise.resolve();
  jest.mocked(getGlobal).mockReturnValue(makeGlobal([REMOVED, SURVIVOR, ADDED_DURING_REQUEST]));
  pending.resolve({ ok: true });
  await result;

  expect(callApi).toHaveBeenCalledWith('unsubscribeNotifications', {
    userToken: 'user-token', addresses: [{ address: `${REMOVED}-address` }],
  });
  expect(getGlobal().pushNotifications.enabledAccounts).toEqual([SURVIVOR, ADDED_DURING_REQUEST]);
});

it('retains accounts added while an all-current-accounts unsubscribe is pending', async () => {
  const pending = deferred<{ ok: true }>();
  jest.mocked(callApi).mockReturnValue(pending.promise);
  const initial = makeGlobal([REMOVED, SURVIVOR]);
  jest.mocked(getGlobal).mockReturnValue(initial);

  const result = deleteAllHandler(initial, {});
  await Promise.resolve();
  jest.mocked(getGlobal).mockReturnValue(makeGlobal([REMOVED, SURVIVOR, ADDED_DURING_REQUEST]));
  pending.resolve({ ok: true });
  await result;

  expect(getGlobal().pushNotifications.enabledAccounts).toEqual([ADDED_DURING_REQUEST]);
});

it('rolls back only accounts added by a failed toggle-all subscription', async () => {
  jest.mocked(callApi).mockResolvedValue(undefined);
  jest.mocked(selectNotificationAddressesSlow).mockReturnValue({
    [REMOVED]: [{ address: `${REMOVED}-address`, chain: 'ton' }],
  });
  const initial = makeGlobal([SURVIVOR]);
  jest.mocked(getGlobal).mockReturnValue(initial);

  const result = toggleHandler(initial, {}, { isEnabled: true } as never);
  await Promise.resolve();
  jest.mocked(getGlobal).mockReturnValue(makeGlobal([SURVIVOR, REMOVED, ADDED_DURING_REQUEST]));
  await result;

  expect(getGlobal().pushNotifications.enabledAccounts).toEqual([SURVIVOR, ADDED_DURING_REQUEST]);
});
