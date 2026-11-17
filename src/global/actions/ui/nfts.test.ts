import './nfts';

import type { GlobalState } from '../../types';
import { ContentTab } from '../../types';

import { addActionHandler } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function selectNfts(activeContentTab: ContentTab, nfts: AnyLiteral = {}, isAgentOpen = false) {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === 'selectNfts');
  const actions = { selectToken: jest.fn(), setActiveContentTab: jest.fn() };
  const global = {
    isAgentOpen,
    auth: {},
    accounts: { byId: { [ACCOUNT_ID]: {} } },
    currentAccountId: ACCOUNT_ID,
    byAccountId: { [ACCOUNT_ID]: { activeContentTab, nfts } },
  };

  (call![1] as ActionHandler)(global as unknown as GlobalState, actions, { nfts: [{ address: 'nft' }] });

  return actions.setActiveContentTab;
}

describe('selectNfts', () => {
  it('opens the collectibles list when selecting outside of it', () => {
    expect(selectNfts(ContentTab.Overview)).toHaveBeenCalledWith({ tab: ContentTab.Nft });
  });

  it('stays in the collectibles list', () => {
    expect(selectNfts(ContentTab.Nft)).not.toHaveBeenCalled();
  });

  it('stays in an open collection', () => {
    const nfts = { currentCollection: { chain: 'ton', address: 'address' } };

    expect(selectNfts(ContentTab.Overview, nfts)).not.toHaveBeenCalled();
  });

  it('leaves the wallet as it is when another section covers it', () => {
    expect(selectNfts(ContentTab.Overview, {}, true)).not.toHaveBeenCalled();
  });
});
