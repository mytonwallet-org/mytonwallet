import './misc';

import type { GlobalState } from '../../types';
import { ContentTab } from '../../types';

import { addActionHandler, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';
import { updatePerpsNavigation } from '../../reducers/perps';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => GlobalState | undefined;
type ActionHandlerWithPayload = (global: GlobalState, actions: AnyLiteral, payload: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

function switchToWallet(activeContentTab?: ContentTab, nfts?: AnyLiteral, isFuturesOpen?: boolean) {
  const actions = {
    closeNftCollection: jest.fn(),
    clearNftsSelection: jest.fn(),
    closeAgent: jest.fn(),
    closeExplore: jest.fn(),
    closeMarket: jest.fn(),
    closeFutures: jest.fn(),
    closeSettings: jest.fn(),
    closePortfolio: jest.fn(),
    selectToken: jest.fn(),
    setActiveContentTab: jest.fn(),
  };
  const global = {
    currentAccountId: ACCOUNT_ID,
    byAccountId: { [ACCOUNT_ID]: { activeContentTab, nfts } },
    isFuturesOpen,
  };

  getHandler('switchToWallet')(global as unknown as GlobalState, actions);

  return actions;
}

describe('switchToWallet', () => {
  it('opens Overview, where the full lists stay behind a back button', () => {
    expect(switchToWallet(ContentTab.Assets).setActiveContentTab).toHaveBeenCalledWith(
      { tab: ContentTab.Overview },
      expect.anything(),
    );
  });

  it('leaves the tab alone when the home tab is already open', () => {
    expect(switchToWallet(ContentTab.Overview).setActiveContentTab).not.toHaveBeenCalled();
  });

  it('closes a collection opened from the home tab', () => {
    const actions = switchToWallet(ContentTab.Overview, { currentCollection: { chain: 'ton', address: 'address' } });

    expect(actions.closeNftCollection).toHaveBeenCalledTimes(1);
    expect(actions.clearNftsSelection).not.toHaveBeenCalled();
  });

  it('clears a selection made in the list of collectibles', () => {
    const actions = switchToWallet(ContentTab.Nft, { selectedNfts: [{ address: 'nft' }] });

    expect(actions.closeNftCollection).not.toHaveBeenCalled();
    expect(actions.clearNftsSelection).toHaveBeenCalledTimes(1);
  });

  it('closes Futures without switching the content tab', () => {
    const actions = switchToWallet(ContentTab.Assets, undefined, true);

    expect(actions.closeFutures).toHaveBeenCalled();
    expect(actions.setActiveContentTab).not.toHaveBeenCalled();
  });
});

describe('closeFuturesScreen', () => {
  it('goes back from an inner screen to the Futures home', () => {
    const global = updatePerpsNavigation(INITIAL_STATE, { screen: 'position', assetId: 'hyperliquid:hl:BTC' });

    expect(getHandler('closeFuturesScreen')(global, {})?.perps.navigation).toEqual({ screen: 'home' });
  });

  it('changes nothing on the Futures home', () => {
    expect(getHandler('closeFuturesScreen')(INITIAL_STATE, {})).toBeUndefined();
  });

  it('returns a screen opened from the Wallet screen to it and keeps the screen while Futures slides away', () => {
    const actions = { switchToWallet: jest.fn() };
    const global = updatePerpsNavigation(
      INITIAL_STATE,
      { screen: 'position', assetId: 'hyperliquid:hl:BTC', isOpenedFromWallet: true },
    );

    expect(getHandler('closeFuturesScreen')(global, actions)).toBeUndefined();
    expect(actions.switchToWallet).toHaveBeenCalledTimes(1);
  });
});

describe('switchToFutures after a screen of the Wallet screen', () => {
  const SECTION_ACTIONS = {
    openFutures: jest.fn(),
    closeAgent: jest.fn(),
    closeExplore: jest.fn(),
    closeSettings: jest.fn(),
    closePortfolio: jest.fn(),
  };

  function getOpenedNavigation(isOpenedFromWallet?: true) {
    (setGlobal as jest.Mock).mockClear();
    const global = updatePerpsNavigation(
      INITIAL_STATE,
      { screen: 'position', assetId: 'hyperliquid:hl:BTC', isOpenedFromWallet },
    );

    getHandler('switchToFutures')(global, SECTION_ACTIONS);

    return ((setGlobal as jest.Mock).mock.calls.at(-1)![0] as GlobalState).perps.navigation;
  }

  it('opens the Futures home instead of the screen the Wallet screen left', () => {
    expect(getOpenedNavigation(true)).toEqual({ screen: 'home' });
  });

  it('keeps the screen Futures was left on', () => {
    expect(getOpenedNavigation()).toEqual({ screen: 'position', assetId: 'hyperliquid:hl:BTC' });
  });
});

describe('switchToFutures', () => {
  it.each([
    ['opens Futures for a wallet with an Arbitrum address', true],
    ['opens Futures for a wallet without an Arbitrum address, which browses the markets, as on iOS', false],
  ])('%s', (_, hasArbitrum) => {
    const actions = {
      showDialog: jest.fn(),
      openFutures: jest.fn(),
      closeAgent: jest.fn(),
      closeExplore: jest.fn(),
      closeSettings: jest.fn(),
      closePortfolio: jest.fn(),
    };
    const global = {
      ...INITIAL_STATE,
      currentAccountId: ACCOUNT_ID,
      accounts: {
        byId: {
          [ACCOUNT_ID]: {
            type: 'mnemonic',
            byChain: { ton: { address: 'ton-address' }, ...(hasArbitrum && { arbitrum: { address: '0x1' } }) },
          },
        },
      },
    };

    getHandler('switchToFutures')(global as unknown as GlobalState, actions);

    expect(actions.openFutures).toHaveBeenCalledTimes(1);
    expect(actions.showDialog).not.toHaveBeenCalled();
  });
});

describe('a tap on the open tab', () => {
  it('returns Futures to its home screen', () => {
    const actions = { openFutures: jest.fn() };
    const global = updatePerpsNavigation(
      { ...INITIAL_STATE, isFuturesOpen: true },
      { screen: 'section', sectionId: 'positions' },
    );

    expect(getHandler('switchToFutures')(global, actions)!.perps.navigation).toEqual({ screen: 'home' });
    expect(actions.openFutures).not.toHaveBeenCalled();
  });

  it('returns Market to its showcase from a section and a token', () => {
    const actions = { openMarket: jest.fn(), closeTokenActivity: jest.fn() };
    const global = {
      ...INITIAL_STATE,
      isMarketOpen: true,
      marketSectionId: 'trending',
      marketTokenSlug: 'toncoin',
      currentAccountId: ACCOUNT_ID,
      byAccountId: { [ACCOUNT_ID]: { currentTokenSlug: 'toncoin' } },
    } as unknown as GlobalState;

    getHandler('switchToMarket')(global, actions);

    expect(setGlobal).toHaveBeenLastCalledWith(expect.objectContaining({ marketSectionId: undefined }));
    expect(actions.closeTokenActivity).toHaveBeenCalledTimes(1);
    expect(actions.openMarket).not.toHaveBeenCalled();
  });
});

describe('openFuturesSection', () => {
  it('opens the section over an open Futures, which a tap on the tab would reset', () => {
    const actions = { openFutures: jest.fn() };

    getHandler('openFuturesSection')({ ...INITIAL_STATE, isFuturesOpen: true }, actions, { sectionId: 'positions' });

    expect(setGlobal).toHaveBeenLastCalledWith(expect.objectContaining({
      perps: expect.objectContaining({ navigation: { screen: 'section', sectionId: 'positions' } }),
    }));
    expect(actions.openFutures).toHaveBeenCalledTimes(1);
  });
});

function openMarketToken(accountState: AnyLiteral) {
  const actions = { selectToken: jest.fn() };
  const global = {
    auth: {},
    accounts: { byId: { [ACCOUNT_ID]: {} } },
    currentAccountId: ACCOUNT_ID,
    byAccountId: { [ACCOUNT_ID]: accountState },
  };

  (setGlobal as jest.Mock).mockClear();
  (getHandler('openMarketToken') as ActionHandlerWithPayload)(global as unknown as GlobalState, actions, {
    slug: 'toncoin',
  });

  const [savedGlobal] = (setGlobal as jest.Mock).mock.calls[0];

  return (savedGlobal as GlobalState).byAccountId[ACCOUNT_ID].activeContentTab;
}

describe('openMarketToken', () => {
  it('keeps the full list of activity open under the market', () => {
    expect(openMarketToken({ activeContentTab: ContentTab.Activity })).toBe(ContentTab.Activity);
  });

  it('returns the wallet to where its token was opened from', () => {
    const state = {
      activeContentTab: ContentTab.Activity,
      activityReturnContentTab: ContentTab.Assets,
      currentTokenSlug: 'other',
    };

    expect(openMarketToken(state)).toBe(ContentTab.Assets);
  });
});

describe('openAgentNewsDiscussion', () => {
  it('switches to the agent with the request for the discussion', () => {
    const switchToAgent = jest.fn();
    const handler = getHandler('openAgentNewsDiscussion') as ActionHandlerWithPayload;

    handler({ isAgentOpen: undefined } as GlobalState, { switchToAgent }, { eventId: 7 });

    expect(setGlobal).toHaveBeenCalledWith(expect.objectContaining({ agentNewsDiscussionRequest: { eventId: 7 } }));
    expect(switchToAgent).toHaveBeenCalledTimes(1);
  });
});

describe('clearAgentNewsDiscussionRequest', () => {
  it('clears the request it consumed, and keeps one stored after it', () => {
    const handler = getHandler('clearAgentNewsDiscussionRequest') as ActionHandlerWithPayload;
    const consumed = { eventId: 7 };

    expect(handler({ agentNewsDiscussionRequest: consumed } as GlobalState, {}, { request: consumed }))
      .toEqual({ agentNewsDiscussionRequest: undefined });
    expect(handler({ agentNewsDiscussionRequest: { eventId: 8 } } as GlobalState, {}, { request: consumed }))
      .toBeUndefined();
  });
});
