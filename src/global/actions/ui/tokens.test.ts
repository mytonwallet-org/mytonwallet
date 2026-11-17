import './tokens';

import type { GlobalState } from '../../types';
import { ContentTab } from '../../types';

import { addActionHandler, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function showTokenActivity(accountState: AnyLiteral, returnTab?: ContentTab, globalPart: AnyLiteral = {}) {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === 'showTokenActivity');
  const actions = { selectToken: jest.fn(), setActiveContentTab: jest.fn() };
  const global = {
    auth: {},
    accounts: { byId: { [ACCOUNT_ID]: {} } },
    currentAccountId: ACCOUNT_ID,
    ...globalPart,
    byAccountId: { [ACCOUNT_ID]: accountState },
  };

  (setGlobal as jest.Mock).mockClear();
  (call![1] as ActionHandler)(global as unknown as GlobalState, actions, { slug: 'toncoin', returnTab });

  const [savedGlobal] = (setGlobal as jest.Mock).mock.calls[0] ?? [];

  return (savedGlobal as GlobalState | undefined)?.byAccountId[ACCOUNT_ID].activityReturnContentTab;
}

// Market is open, and its token is the selected one
const MARKET_TOKEN_OPEN = { isMarketOpen: true, marketTokenSlug: 'other' };

function runTokenAction(name: string, globalPart: AnyLiteral, accountState: AnyLiteral) {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  const actions = { selectToken: jest.fn(), setActiveContentTab: jest.fn() };
  const currentTokenSlug = globalPart.marketTokenSlug ?? accountState.currentTokenSlug;
  const global = {
    auth: {},
    accounts: { byId: { [ACCOUNT_ID]: {} } },
    currentAccountId: ACCOUNT_ID,
    ...globalPart,
    byAccountId: { [ACCOUNT_ID]: { ...accountState, currentTokenSlug } },
  };

  (setGlobal as jest.Mock).mockClear();
  (call![1] as ActionHandler)(global as unknown as GlobalState, actions, { slug: 'toncoin' });

  return { actions };
}

describe('showTokenActivity', () => {
  it('stores the given return tab', () => {
    expect(showTokenActivity({ activeContentTab: ContentTab.Overview }, ContentTab.Assets)).toBe(ContentTab.Assets);
  });

  it('returns to the current tab when no return tab is given', () => {
    const state = { activeContentTab: ContentTab.Overview, activityReturnContentTab: ContentTab.Assets };

    expect(showTokenActivity(state)).toBe(ContentTab.Overview);
  });

  it('leaves the wallet tab alone when a token opens over a market token', () => {
    const { actions } = runTokenAction('showTokenActivity', MARKET_TOKEN_OPEN, { activeContentTab: ContentTab.Assets });

    expect(actions.selectToken).toHaveBeenCalledWith({ slug: 'toncoin' }, { forceOnHeavyAnimation: true });
    expect(actions.setActiveContentTab).not.toHaveBeenCalled();
    expect(setGlobal).not.toHaveBeenCalled();
  });

  it('opens the wallet token while a closed market still keeps its token', () => {
    const { actions } = runTokenAction(
      'showTokenActivity',
      { ...MARKET_TOKEN_OPEN, isMarketOpen: undefined },
      { activeContentTab: ContentTab.Assets },
    );

    expect(actions.setActiveContentTab).toHaveBeenCalledWith({ tab: ContentTab.Activity });
  });

  it('stores the wallet place over the token of a closed market', () => {
    const state = { activeContentTab: ContentTab.Assets, currentTokenSlug: 'other' };

    expect(showTokenActivity(state, undefined, { marketTokenSlug: 'other' })).toBe(ContentTab.Assets);
  });

  it('keeps the return tab when a token opens from another token', () => {
    const state = {
      activeContentTab: ContentTab.Activity,
      activityReturnContentTab: ContentTab.Assets,
      currentTokenSlug: 'other',
    };

    expect(showTokenActivity(state)).toBeUndefined();
  });
});

describe('closeTokenActivity', () => {
  it('returns the wallet to where its token was opened from', () => {
    const { actions } = runTokenAction('closeTokenActivity', {}, {
      activeContentTab: ContentTab.Activity,
      activityReturnContentTab: ContentTab.Assets,
      currentTokenSlug: 'toncoin',
    });

    expect(actions.setActiveContentTab).toHaveBeenCalledWith({ tab: ContentTab.Assets });
  });

  it('leaves the wallet tab alone when a market token closes', () => {
    const { actions } = runTokenAction(
      'closeTokenActivity',
      MARKET_TOKEN_OPEN,
      { activeContentTab: ContentTab.Activity },
    );

    expect(actions.selectToken).toHaveBeenCalledWith({ slug: undefined }, { forceOnHeavyAnimation: true });
    expect(actions.setActiveContentTab).not.toHaveBeenCalled();
  });
});
