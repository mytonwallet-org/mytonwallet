import './misc';

import type { GlobalState } from '../../types';
import { ContentTab } from '../../types';

import { addActionHandler } from '../../index';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../hooks/useDeviceScreen', () => ({
  getIsPortrait: jest.fn(),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

function switchToWallet({ isPortrait, activeContentTab }: { isPortrait: boolean; activeContentTab?: ContentTab }) {
  (getIsPortrait as jest.Mock).mockReturnValue(isPortrait);

  const actions = {
    closeAgent: jest.fn(),
    closeExplore: jest.fn(),
    closeMarket: jest.fn(),
    closeSettings: jest.fn(),
    closePortfolio: jest.fn(),
    selectToken: jest.fn(),
    setActiveContentTab: jest.fn(),
  };
  const global = { currentAccountId: ACCOUNT_ID, byAccountId: { [ACCOUNT_ID]: { activeContentTab } } };

  getHandler('switchToWallet')(global as unknown as GlobalState, actions);

  return actions.setActiveContentTab;
}

describe('switchToWallet', () => {
  it('opens Overview on desktop, where Assets is a full-list page behind a back button', () => {
    expect(switchToWallet({ isPortrait: false })).toHaveBeenCalledWith(
      { tab: ContentTab.Overview },
      expect.anything(),
    );
  });

  it('opens Assets on mobile', () => {
    expect(switchToWallet({ isPortrait: true })).toHaveBeenCalledWith(
      { tab: ContentTab.Assets },
      expect.anything(),
    );
  });

  it('leaves the tab alone when the home tab is already open', () => {
    expect(switchToWallet({ isPortrait: false, activeContentTab: ContentTab.Overview })).not.toHaveBeenCalled();
  });
});
