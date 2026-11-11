import type {
  ApiAccountAny, ApiBalanceBySlug, ApiChain, ApiForeignStakingProvider,
  ApiUpdateAccountBanners, ApiUpdateAccountConfig, ApiUpdateConfig, OnApiUpdate,
} from '../types';

import { TONCOIN, TONSTAKERS_JETTON, TRC20_USDT_MAINNET } from '../../config';
import * as chainUtils from '../../util/chain';
import Deferred from '../../util/Deferred';
import { setIsAppFocused } from '../../util/focusAwareDelay';
import { logDebugError } from '../../util/logs';
import {
  applyPendingBalances, capturePendingTransferBalances, clearPendingBalances, registerPendingTransfer,
} from '../common/pendingBalances';
import { buildTokenSlug } from '../common/tokens';
import { MINUTE } from '../constants';

const mockCallBackendGet = jest.fn();
const mockCallBackendPost = jest.fn();
const mockForeign = jest.fn();
const mockStakingCommon = jest.fn();
const mockAccount = jest.fn();
const mockAccounts = jest.fn();
const mockRefreshMfaStateAndNotify = jest.fn();
const mockSetPerpsAssetsUpdater = jest.fn();
const mockLoadPerpsAssetsCache = jest.fn();
const mockRefreshPerpsAssets = jest.fn();
const mockOnUpdate = jest.fn<void, Parameters<OnApiUpdate>>();
const mockSetupActivePolling = jest.fn(
  (_accountId: string, _account: ApiAccountAny, _onUpdate: OnApiUpdate) => jest.fn(),
);
const mockSetupInactivePolling = jest.fn(
  (_accountId: string, _account: ApiAccountAny, _onUpdate: OnApiUpdate) => jest.fn(),
);
let mockNoExtraFeatures = true;
let mockUseRealPollingLoop = false;
let mockIsIosApp = false;
let mockIsPerpsEnabled = true;

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  get NO_EXTRA_FEATURES() { return mockNoExtraFeatures; },
  get IS_PERPS_ENABLED() { return mockIsPerpsEnabled; },
}));

jest.mock('../../util/logs', () => ({
  ...jest.requireActual('../../util/logs'), logDebugError: jest.fn(),
}));

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: {
      setupActivePolling: mockSetupActivePolling,
      setupInactivePolling: mockSetupInactivePolling,
    },
    ethereum: {
      setupActivePolling: mockSetupActivePolling,
      setupInactivePolling: mockSetupInactivePolling,
    },
    arbitrum: {
      setupActivePolling: mockSetupActivePolling,
      setupInactivePolling: mockSetupInactivePolling,
    },
  },
}));

jest.mock('./optional', () => ({
  requireAgentV2Lifecycle: () => ({
    reconcileAgentV2ProtocolVersion: jest.fn().mockResolvedValue(undefined),
    resolveAgentV2ProtocolVersionForRouting: (version?: string) => version,
  }),
  requireMfaMethods: () => ({
    refreshMfaStateAndNotify: (...args: unknown[]) => mockRefreshMfaStateAndNotify(...args),
  }),
  requireStakingMethods: () => ({
    fetchStakingForeign: (...args: unknown[]) => mockForeign(...args),
    tryUpdateStakingCommonData: jest.fn().mockResolvedValue(undefined),
  }),
  requireSwapMethods: () => ({ swapGetAssetsText: jest.fn().mockResolvedValue('[]') }),
  requirePerpsAssets: () => ({
    setPerpsAssetsUpdater: (...args: unknown[]) => mockSetPerpsAssetsUpdater(...args),
    loadPerpsAssetsCache: (...args: unknown[]) => mockLoadPerpsAssetsCache(...args),
    refreshPerpsAssets: (...args: unknown[]) => mockRefreshPerpsAssets(...args),
  }),
  requirePerpsPositions: () => ({ setupPerpsPositionsPolling: () => undefined }),
}));

jest.mock('../environment', () => ({ getEnvironment: () => ({ isIosApp: mockIsIosApp }) }));

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: (...args: unknown[]) => mockAccount(...args),
  fetchMaybeStoredAccount: (...args: unknown[]) => mockAccount(...args),
  fetchStoredAccounts: () => mockAccounts(),
  doesAccountHaveChain: (account: ApiAccountAny, chain: keyof ApiAccountAny['byChain']) => (
    Boolean(account.byChain[chain])
  ),
}));

jest.mock('../common/addresses', () => ({
  tryUpdateKnownAddresses: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../common/backend', () => ({
  callBackendGet: (...args: unknown[]) => mockCallBackendGet(...args),
  callBackendPost: (...args: unknown[]) => mockCallBackendPost(...args),
}));

jest.mock('../common/cache', () => ({
  setBackendConfigCache: jest.fn(),
  getBackendConfigCacheSync: jest.fn().mockReturnValue({}),
  getStakingCommonCacheSync: jest.fn(),
  getStakingCommonCache: (...args: unknown[]) => mockStakingCommon(...args),
}));

jest.mock('../common/polling/utils', () => ({
  pollingLoop: (options: { poll: () => Promise<void> }) => (mockUseRealPollingLoop
    ? jest.requireActual('../common/polling/utils').pollingLoop(options)
    : { poll: options.poll, stop: jest.fn() }),
}));

jest.mock('../common/tokens', () => ({
  buildTokenSlug: (...args: unknown[]) => jest.requireActual('../common/tokens').buildTokenSlug(...args),
  fetchNonBackendTokenDetails: jest.fn().mockResolvedValue([]),
  loadTokensCache: jest.fn().mockResolvedValue(undefined),
  pauseTokenUpdates: jest.fn(),
  resumeTokenUpdates: jest.fn(),
  sendUpdateTokens: jest.fn(),
  tokensPreload: { promise: Promise.resolve() },
  updateTokens: jest.fn(),
  updateTokensFromBackend: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn().mockResolvedValue(undefined),
  },
}));

jest.mock('./preload', () => ({
  resolveDataPreloadPromise: jest.fn(),
}));

describe('Perps catalogue polling', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    mockNoExtraFeatures = false;
    mockUseRealPollingLoop = true;
    mockAccounts.mockReset().mockResolvedValue({});
    mockCallBackendGet.mockReset().mockResolvedValue({});
    mockSetPerpsAssetsUpdater.mockClear();
    mockLoadPerpsAssetsCache.mockReset().mockResolvedValue(undefined);
    mockRefreshPerpsAssets.mockReset().mockResolvedValue({ assetsByChain: {} });
  });

  afterEach(async () => {
    const { destroyPolling } = await import('./polling');
    await destroyPolling();
    mockNoExtraFeatures = true;
    mockUseRealPollingLoop = false;
    mockIsIosApp = false;
    mockIsPerpsEnabled = true;
    mockCallBackendGet.mockReset();
    jest.clearAllTimers();
    jest.useRealTimers();
  });

  it('restores the catalogue and refreshes it every minute in the iOS app', async () => {
    mockIsIosApp = true;
    const { initPolling } = await import('./polling');
    initPolling(mockOnUpdate);

    await jest.advanceTimersByTimeAsync(0);
    expect(mockLoadPerpsAssetsCache).toHaveBeenCalledTimes(1);
    expect(mockRefreshPerpsAssets).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(MINUTE);
    expect(mockRefreshPerpsAssets).toHaveBeenCalledTimes(2);
  });

  it('does not read the catalogue in the iOS app while Perps is closed', async () => {
    mockIsIosApp = true;
    mockIsPerpsEnabled = false;
    const { initPolling } = await import('./polling');
    initPolling(mockOnUpdate);

    await jest.advanceTimersByTimeAsync(2 * MINUTE);
    expect(mockLoadPerpsAssetsCache).not.toHaveBeenCalled();
    expect(mockRefreshPerpsAssets).not.toHaveBeenCalled();
  });

  it('does not read the catalogue on other clients but still publishes what they load', async () => {
    const { initPolling } = await import('./polling');
    initPolling(mockOnUpdate);

    await jest.advanceTimersByTimeAsync(2 * MINUTE);
    expect(mockSetPerpsAssetsUpdater).toHaveBeenCalledTimes(1);
    expect(mockLoadPerpsAssetsCache).not.toHaveBeenCalled();
    expect(mockRefreshPerpsAssets).not.toHaveBeenCalled();
  });
});

describe('backend config polling', () => {
  beforeEach(() => {
    mockNoExtraFeatures = true;
    mockAccounts.mockReset().mockResolvedValue({});
    mockRefreshMfaStateAndNotify.mockReset().mockResolvedValue(undefined);
    mockForeign.mockReset().mockResolvedValue([]);
    mockCallBackendPost.mockReset().mockResolvedValue({ cardsInfo: {} });
    mockStakingCommon.mockReset().mockResolvedValue({ liquid: { apy: 5 } });
    mockCallBackendGet.mockImplementation((path: string) => {
      if (path === '/utils/get-config') {
        return Promise.resolve({
          agentProtocolVersion: 'v2',
          country: 'DE',
          isLimited: false,
          isUpdateRequired: false,
          now: Date.now(),
        });
      }

      if (path === '/currency-rates') {
        return Promise.resolve({ rates: {} });
      }

      if (path === '/staking/foreign') return Promise.resolve([]);

      return Promise.resolve({});
    });
  });

  afterEach(() => {
    mockCallBackendGet.mockReset();
  });

  it('forwards the agent protocol version from the backend config update', async () => {
    const { destroyPolling, initPolling } = await import('./polling');
    const updatePromise = new Promise<ApiUpdateConfig>((resolve) => {
      initPolling((update) => {
        if (update.type === 'updateConfig') resolve(update);
      });
    });

    await expect(updatePromise).resolves.toMatchObject({
      type: 'updateConfig',
      agentProtocolVersion: 'v2',
    });

    await destroyPolling();
  });

  it('forwards the swap and on-ramp limit from the backend config update', async () => {
    mockCallBackendGet.mockImplementation((path: string) => {
      if (path === '/utils/get-config') {
        return Promise.resolve({
          country: 'DE',
          isLimited: true,
          isSwapAndOnRampLimited: false,
          isUpdateRequired: false,
          now: Date.now(),
        });
      }

      if (path === '/currency-rates') return Promise.resolve({ rates: {} });
      return Promise.resolve({});
    });
    const { destroyPolling, initPolling } = await import('./polling');
    const updatePromise = new Promise<ApiUpdateConfig>((resolve) => {
      initPolling((update) => {
        if (update.type === 'updateConfig') resolve(update);
      });
    });

    await expect(updatePromise).resolves.toMatchObject({ isLimited: true, isSwapAndOnRampLimited: false });

    await destroyPolling();
  });

  it('does not forward an unsupported agent protocol version', async () => {
    mockCallBackendGet.mockImplementation((path: string) => {
      if (path === '/utils/get-config') {
        return Promise.resolve({
          agentProtocolVersion: 'v3',
          country: 'DE',
          isLimited: false,
          isUpdateRequired: false,
          now: Date.now(),
        });
      }

      if (path === '/currency-rates') return Promise.resolve({ rates: {} });
      return Promise.resolve({});
    });
    const { destroyPolling, initPolling } = await import('./polling');
    const updatePromise = new Promise<ApiUpdateConfig>((resolve) => {
      initPolling((update) => {
        if (update.type === 'updateConfig') resolve(update);
      });
    });

    await expect(updatePromise).resolves.toMatchObject({
      type: 'updateConfig',
      agentProtocolVersion: undefined,
    });

    await destroyPolling();
  });

  it('delivers SDK Home and Staking banners in one account-banners update', async () => {
    const provider: ApiForeignStakingProvider = {
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts',
      unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    };
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [
      provider, { ...provider, name: 'equal', apy: 5 }, { ...provider, name: 'higher', apy: 6 },
      { ...provider, name: 'empty', amount: 0n },
      { ...provider, name: 'future', provider: 'future' },
    ] }]);
    const { config, banners } = await pollAccount('0-mainnet');
    expect(config).toEqual({ cardsInfo: {} });
    expect(banners.stakingBanners[0]).toMatchObject({
      id: 'foreign-staking:ton:tonstakers',
      kind: 'foreignStaking',
      foreignStaking: {
        chain: 'ton',
        providerName: 'tonstakers',
        amount: '12\u202F345.67',
        symbol: TONCOIN.symbol,
        apy: 3,
        stakingApy: 5,
      },
      infoBanner: {
        title: '🔒 %amount% %symbol% staked elsewhere',
        textValues: { '%amount%': '12\u202F345.67', '%symbol%': TONCOIN.symbol },
        description: 'Unlock your %symbol% to access higher-yield staking.',
        actionButton: { title: 'Unstake', onClickAction: 'unstakeForeign', chain: 'ton', providerName: 'tonstakers' },
      },
      linkedBannerId: 'foreign-staking:ton',
    });
    expect(banners.homeBanners).toEqual([{
      id: 'foreign-staking:ton',
      kind: 'infoBanner',
      infoBanner: {
        title: '💎 Higher-yield staking available',
        textValues: { '%symbol%': TONCOIN.symbol },
        description: 'Tap to restake your %symbol% with higher returns.',
        actionButton: { title: 'Restake Now', onClickAction: 'openEarn' },
      },
    }]);
  });

  it.each([false, true])('keeps server banners across staking updates (foreign first: %s)', async (foreignFirst) => {
    const serverBanner = {
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Server offer', description: 'Earn rewards',
        actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    };
    const serverPromotion = {
      id: 'server-card', kind: 'cardOverlay', cardOverlay: { onClickAction: 'openMintCardModal' },
    };
    const nextServerPromotion = { ...serverPromotion, id: 'next-server-card' };
    mockCallBackendPost.mockResolvedValue({
      cardsInfo: {}, activePromotion: serverPromotion, infoBanners: [serverBanner],
    });
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [{
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    }] }]);
    const { config, banners, updates } = await pollAccount('0-mainnet', 'mnemonic', async (poll) => {
      mockCallBackendPost.mockResolvedValue({
        cardsInfo: {}, activePromotion: nextServerPromotion, infoBanners: [serverBanner],
      });
      await poll.config();
      mockForeign.mockResolvedValue([]);
      await poll.foreign();
    }, foreignFirst);

    expect(config).toEqual({ cardsInfo: {}, activePromotion: nextServerPromotion });
    expect(updates.at(-2)).toMatchObject({
      stakingBanners: [expect.objectContaining({ id: 'foreign-staking:ton:tonstakers' })],
    });
    expect(updates.at(-2)?.homeBanners.map(({ id }) => id)).toEqual(['foreign-staking:ton', 'server-banner']);
    expect(banners).toEqual({
      type: 'updateAccountBanners', accountId: '0-mainnet', homeBanners: [serverBanner], stakingBanners: [],
    });
  });

  it('clears staking banners when no foreign stake remains', async () => {
    mockForeign.mockResolvedValue([]);
    const { config, banners } = await pollAccount('0-mainnet');
    expect(config).toEqual({ cardsInfo: {} });
    expect(banners.homeBanners).toEqual([]);
    expect(banners.stakingBanners).toEqual([]);
  });

  /* eslint-disable no-null/no-null */
  it('keeps only supported server banners alongside foreign staking banners', async () => {
    const serverBanner = {
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Server offer', description: 'Earn rewards',
        actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    };
    mockCallBackendPost.mockResolvedValue({ cardsInfo: {}, infoBanners: [
      serverBanner,
      { ...serverBanner, id: 'unknown-kind', kind: 'futureBanner' },
      { ...serverBanner, id: 'unknown-action', infoBanner: {
        ...serverBanner.infoBanner, actionButton: { title: 'Swap', onClickAction: 'openSwap' },
      } },
      { ...serverBanner, id: 'server-unstake', infoBanner: {
        ...serverBanner.infoBanner,
        actionButton: { title: 'Unstake', onClickAction: 'unstakeForeign', chain: 'ton', providerName: 'tonstakers' },
      } },
      null,
      { ...serverBanner, id: 'missing-info', infoBanner: null },
      { ...serverBanner, id: 'invalid-title', infoBanner: { ...serverBanner.infoBanner, title: 1 } },
      { ...serverBanner, id: 'invalid-description', infoBanner: { ...serverBanner.infoBanner, description: 1 } },
      { ...serverBanner, id: 'missing-action', infoBanner: { ...serverBanner.infoBanner, actionButton: null } },
      { ...serverBanner, id: 'invalid-action-title', infoBanner: {
        ...serverBanner.infoBanner, actionButton: { title: 1, onClickAction: 'openEarn' },
      } },
    ] });
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [{
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    }] }]);

    const { banners } = await pollAccount('0-mainnet');

    expect(banners.homeBanners).toEqual([
      expect.objectContaining({ id: 'foreign-staking:ton' }), serverBanner,
    ]);
    expect(banners.stakingBanners).toEqual([
      expect.objectContaining({ id: 'foreign-staking:ton:tonstakers' }),
    ]);
  });

  it.each([null, undefined, {}, 'invalid'])('treats non-array server banners (%p) as empty', async (infoBanners) => {
    const serverBanner = {
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Server offer', description: 'Earn rewards',
        actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    };
    mockCallBackendPost.mockResolvedValue({ cardsInfo: {}, infoBanners: [serverBanner] });

    const { banners, updates } = await pollAccount('0-mainnet', 'mnemonic', async (poll) => {
      mockCallBackendPost.mockResolvedValue({ cardsInfo: {}, infoBanners });
      await poll.config();
    });

    expect(updates[0].homeBanners).toEqual([serverBanner]);
    expect(banners.homeBanners).toEqual([]);
  });
  /* eslint-enable no-null/no-null */

  it('clears cached foreign banners when the first balance after reactivation is zero', async () => {
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [{
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    }] }]);
    const serverBanner = {
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Offer', description: 'Details', actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    };
    const { updates } = await pollAccount('0-mainnet', 'mnemonic', async (poll) => {
      const { setActivePollingAccount } = await import('./polling');
      await setActivePollingAccount('1-mainnet', {});
      await poll.config();
      await setActivePollingAccount('0-mainnet', {});
      mockCallBackendPost.mockResolvedValue({ infoBanners: [serverBanner] });
      await poll.config();
      const requestCount = mockForeign.mock.calls.length;
      mockSetupActivePolling.mock.lastCall![2]({
        type: 'updateBalances', accountId: '0-mainnet', chain: 'ton', balances: {},
      });
      expect(mockForeign).toHaveBeenCalledTimes(requestCount);
      await setActivePollingAccount('1-mainnet', {});
      await setActivePollingAccount('0-mainnet', {});
      await poll.config();
      mockSetupActivePolling.mock.lastCall![2]({
        type: 'updateBalances', accountId: '0-mainnet', chain: 'ton', balances: {},
      });
    });
    expect(updates.at(-3)).toMatchObject({
      accountId: '0-mainnet',
      stakingBanners: [expect.objectContaining({ id: 'foreign-staking:ton:tonstakers' })],
    });
    expect(updates.at(-3)?.homeBanners.map(({ id }) => id)).toEqual(['foreign-staking:ton', 'server-banner']);
    expect(updates.at(-2)).toMatchObject({ homeBanners: [serverBanner], stakingBanners: [] });
    expect(updates.at(-1)).toMatchObject({ homeBanners: [serverBanner], stakingBanners: [] });
  });

  it('reports banners only after both sources answer', async () => {
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [{
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    }] }]);
    mockCallBackendPost.mockResolvedValue({ infoBanners: [{
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Offer', description: 'Details', actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    }] });

    const { updates } = await pollAccount('0-mainnet');

    expect(updates.map(({ homeBanners }) => homeBanners.map(({ id }) => id))).toEqual([
      ['foreign-staking:ton', 'server-banner'],
    ]);
  });

  it('reports no banners while the foreign staking request fails', async () => {
    mockForeign.mockRejectedValue(new Error('Network error'));
    mockCallBackendPost.mockResolvedValue({ infoBanners: [{
      id: 'server-banner', kind: 'infoBanner',
      infoBanner: {
        title: 'Offer', description: 'Details', actionButton: { title: 'Earn', onClickAction: 'openEarn' },
      },
    }] });

    const { updates } = await pollAccount('0-mainnet');

    expect(updates).toEqual([]);
  });

  it('reports no banners while the account config request fails', async () => {
    mockForeign.mockResolvedValue([{ chain: 'ton', providers: [{
      name: 'tonstakers', amount: 500000000000n, amountNative: 12345678900000n, apy: 3,
      provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
    }] }]);
    mockCallBackendPost.mockRejectedValue(new Error('Network error'));

    const { updates } = await pollAccount('0-mainnet');

    expect(updates).toEqual([]);
  });

  it.each([
    ['0-testnet', 'mnemonic'], ['0-mainnet', 'view'],
  ] as const)('does not fetch foreign staking for %s %s accounts', async (accountId, type) => {
    const { banners } = await pollAccount(accountId, type);
    expect(banners.stakingBanners).toEqual([]);
    expect(mockForeign).not.toHaveBeenCalled();
  });

  describe('pending balance delivery', () => {
    beforeEach(async () => {
      jest.useFakeTimers();
      mockOnUpdate.mockClear();
      mockSetupActivePolling.mockClear();
      mockSetupInactivePolling.mockClear();
      const account: ApiAccountAny = {
        type: 'bip39',
        byChain: {
          ethereum: { address: '0xwallet', index: 0 },
          arbitrum: { address: '0xwallet', index: 0 },
        },
      };
      const accounts = { '0-mainnet': account, '1-mainnet': account };
      mockAccount.mockResolvedValue(account);
      mockAccounts.mockResolvedValue(accounts);
      const { initPolling, setActivePollingAccount } = await import('./polling');
      initPolling(mockOnUpdate);
      await setActivePollingAccount('0-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
    });

    afterEach(async () => {
      const { destroyPolling } = await import('./polling');
      await destroyPolling();
      clearPendingBalances('0-mainnet');
      clearPendingBalances('1-mainnet');
      clearPendingBalances('0-testnet');
      jest.clearAllTimers();
      jest.useRealTimers();
    });

    it.each([
      { kind: 'active', accountId: '0-mainnet' },
      { kind: 'inactive', accountId: '1-mainnet' },
    ])('applies debits to cross-chain balances from $kind polling', ({ kind, accountId }) => {
      const setup = kind === 'active' ? mockSetupActivePolling : mockSetupInactivePolling;
      // The first chain poller is Ethereum; it may report Arbitrum assets from a cross-chain fetch.
      const emit = setup.mock.calls.find(([id]) => id === accountId)![2];
      const slug = chainUtils.getChainConfig('arbitrum').nativeToken.slug;
      const stale = { type: 'updateBalances', accountId, chain: 'arbitrum', balances: { [slug]: 1000n } } as const;
      emit(stale);
      const balancesBeforeTransfer = capturePendingTransferBalances(accountId, 'arbitrum', slug);
      registerPendingTransfer(
        accountId, 'arbitrum', { slug, amount: 200n, fee: 10n }, balancesBeforeTransfer, mockOnUpdate,
      );
      mockOnUpdate.mockClear();

      emit(stale);
      expect(mockOnUpdate).toHaveBeenLastCalledWith({ ...stale, balances: { [slug]: 790n } });
      expect(stale.balances).toEqual({ [slug]: 1000n });

      emit({ ...stale, balances: { [slug]: 900n } });
      expect(mockOnUpdate).toHaveBeenLastCalledWith({ ...stale, balances: { [slug]: 900n } });
    });

    it('preserves pending balances while an account switches to inactive polling and back', async () => {
      const accountId = '0-mainnet';
      const slug = chainUtils.getChainConfig('ethereum').nativeToken.slug;
      const stale = { type: 'updateBalances', accountId, chain: 'ethereum', balances: { [slug]: 1000n } } as const;
      const emitActive = mockSetupActivePolling.mock.calls.find(([id]) => id === accountId)![2];
      emitActive(stale);
      const balancesBeforeTransfer = capturePendingTransferBalances(accountId, 'ethereum', slug);
      registerPendingTransfer(
        accountId, 'ethereum', { slug, amount: 200n, fee: 10n }, balancesBeforeTransfer, mockOnUpdate,
      );
      const { setActivePollingAccount } = await import('./polling');
      mockSetupInactivePolling.mockClear();
      await setActivePollingAccount('1-mainnet', {});
      mockOnUpdate.mockClear();
      const emitInactive = mockSetupInactivePolling.mock.calls.find(([id]) => id === accountId)![2];
      emitInactive(stale);
      expect(mockOnUpdate).toHaveBeenLastCalledWith({ ...stale, balances: { [slug]: 790n } });

      mockSetupActivePolling.mockClear();
      await setActivePollingAccount(accountId, {});
      mockOnUpdate.mockClear();
      const emitReactivated = mockSetupActivePolling.mock.calls.find(([id]) => id === accountId)![2];
      emitReactivated(stale);
      expect(mockOnUpdate).toHaveBeenLastCalledWith({ ...stale, balances: { [slug]: 790n } });
    });

    it.each(['account', 'network', 'all'] as const)('clears pending balances during %s removal', async (scope) => {
      const accountId = '1-mainnet';
      const slug = chainUtils.getChainConfig('ethereum').nativeToken.slug;
      const emit = mockSetupInactivePolling.mock.calls.find(([id]) => id === accountId)![2];
      emit({ type: 'updateBalances', accountId, chain: 'ethereum', balances: { [slug]: 1000n } });
      const balancesBeforeTransfer = capturePendingTransferBalances(accountId, 'ethereum', slug);
      registerPendingTransfer(
        accountId, 'ethereum', { slug, amount: 200n, fee: 10n }, balancesBeforeTransfer, mockOnUpdate,
      );
      const otherNetworkUpdate = {
        type: 'updateBalances', accountId: '0-testnet', chain: 'ethereum', balances: { [slug]: 1000n },
      } as const;
      applyPendingBalances(otherNetworkUpdate);
      const otherNetworkBalances = capturePendingTransferBalances('0-testnet', 'ethereum', slug);
      const {
        removePollingAccount, removeNetworkPollingAccounts, removeAllPollingAccounts,
      } = await import('./polling');
      if (scope === 'account') await removePollingAccount(accountId);
      else if (scope === 'network') await removeNetworkPollingAccounts('mainnet');
      else await removeAllPollingAccounts();
      mockOnUpdate.mockClear();

      await jest.advanceTimersByTimeAsync(15 * MINUTE);
      registerPendingTransfer(
        accountId, 'ethereum', { slug, amount: 200n, fee: 10n }, balancesBeforeTransfer, mockOnUpdate,
      );
      expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'updateBalances' }));

      registerPendingTransfer(
        '0-testnet', 'ethereum', { slug, amount: 200n, fee: 10n }, otherNetworkBalances, mockOnUpdate,
      );
      if (scope === 'all') {
        expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'updateBalances' }));
      } else {
        expect(mockOnUpdate).toHaveBeenLastCalledWith({ ...otherNetworkUpdate, balances: { [slug]: 790n } });
      }
    });
  });

  describe('idle account polling', () => {
    beforeEach(async () => {
      jest.useFakeTimers();
      setIsAppFocused(true);
      mockUseRealPollingLoop = true;
      mockAccount.mockResolvedValue({ type: 'ton', byChain: { ton: { address: 'wallet-address' } } });
      mockOnUpdate.mockClear();
      const { initPolling } = await import('./polling');
      initPolling(mockOnUpdate);
      mockNoExtraFeatures = false;
    });

    afterEach(async () => {
      const { destroyPolling } = await import('./polling');
      await destroyPolling();
      mockUseRealPollingLoop = false;
      jest.clearAllTimers();
      setIsAppFocused(true);
      jest.useRealTimers();
    });

    it.each([
      { isFocused: true, period: 5 * MINUTE },
      { isFocused: false, period: 10 * MINUTE },
    ])('polls account config every $period ms with focus=$isFocused and stops on destroy', async ({
      isFocused, period,
    }) => {
      setIsAppFocused(isFocused);
      const { destroyPolling, setActivePollingAccount } = await import('./polling');
      await setActivePollingAccount('0-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(1);

      await jest.advanceTimersByTimeAsync(period - 1);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(1);
      await jest.advanceTimersByTimeAsync(1);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(2);
      await jest.advanceTimersByTimeAsync(period);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(3);

      await setActivePollingAccount('1-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(4);
      await jest.advanceTimersByTimeAsync(period);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(5);

      await destroyPolling();
      await jest.advanceTimersByTimeAsync(2 * period);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(5);
    });

    it('keeps account config on failure and recovers at the next five-minute poll', async () => {
      const { setActivePollingAccount } = await import('./polling');
      await setActivePollingAccount('0-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
      expect(mockOnUpdate).toHaveBeenCalledWith({
        type: 'updateAccountConfig', accountId: '0-mainnet', accountConfig: { cardsInfo: {} },
      });
      mockOnUpdate.mockClear();
      const error = new Error('Offline');
      mockCallBackendPost.mockRejectedValueOnce(error);

      await jest.advanceTimersByTimeAsync(5 * MINUTE);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(2);
      expect(logDebugError).toHaveBeenCalledWith('setupBackendAccountPolling', error);
      expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'updateAccountConfig' }));
      expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'updateAccountBanners' }));

      mockCallBackendPost.mockResolvedValue({ cardsInfo: {}, isMfaEnabled: true });
      await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(2);
      await jest.advanceTimersByTimeAsync(1);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(3);
      expect(mockOnUpdate).toHaveBeenCalledWith({
        type: 'updateAccountConfig', accountId: '0-mainnet', accountConfig: { cardsInfo: {}, isMfaEnabled: true },
      });
    });

    it.each([
      { type: 'view', isActive: true },
      { type: 'view', isActive: false },
      { type: 'ton', isActive: true },
      { type: 'ton', isActive: false },
    ] as const)('polls MFA only for signing accounts: type=$type active=$isActive', async ({ type, isActive }) => {
      const accounts: Record<string, ApiAccountAny> = {
        '0-mainnet': { type, byChain: { ton: { address: 'wallet-address', index: 0 } } },
        '1-mainnet': { type: 'view', byChain: { ton: { address: 'other-wallet-address', index: 0 } } },
      };
      mockAccount.mockImplementation((accountId: string) => Promise.resolve(accounts[accountId]));
      mockAccounts.mockResolvedValue(accounts);
      const { destroyPolling, setActivePollingAccount } = await import('./polling');
      await setActivePollingAccount(isActive ? '0-mainnet' : '1-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
      const isSigning = type !== 'view';
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 1 : 0);

      await jest.advanceTimersByTimeAsync(MINUTE - 1);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 1 : 0);
      const error = new Error('Offline');
      if (isSigning) mockRefreshMfaStateAndNotify.mockRejectedValueOnce(error);
      await jest.advanceTimersByTimeAsync(1);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 2 : 0);
      if (isSigning) expect(logDebugError).toHaveBeenCalledWith('setupMfaPolling', error);
      await jest.advanceTimersByTimeAsync(MINUTE);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 3 : 0);

      await setActivePollingAccount(isActive ? '1-mainnet' : '0-mainnet', {});
      await jest.advanceTimersByTimeAsync(0);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 4 : 0);
      await jest.advanceTimersByTimeAsync(MINUTE);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 5 : 0);
      expect(mockRefreshMfaStateAndNotify.mock.calls.every(([accountId]) => accountId === '0-mainnet')).toBe(true);

      await destroyPolling();
      await jest.advanceTimersByTimeAsync(10 * MINUTE);
      expect(mockRefreshMfaStateAndNotify).toHaveBeenCalledTimes(isSigning ? 5 : 0);
    });
  });

  describe('foreign staking balance refresh', () => {
    beforeEach(async () => {
      jest.useFakeTimers();
      setIsAppFocused(true);
      mockUseRealPollingLoop = true;
      mockAccount.mockResolvedValue({ type: 'mnemonic', byChain: { ton: { address: 'wallet-address' } } });
      mockForeign.mockImplementation(jest.requireActual('./staking').fetchStakingForeign);
      mockOnUpdate.mockClear();
      const { initPolling } = await import('./polling');
      initPolling(mockOnUpdate);
      mockNoExtraFeatures = false;
    });

    afterEach(async () => {
      const { destroyPolling } = await import('./polling');
      await destroyPolling();
      mockUseRealPollingLoop = false;
      jest.clearAllTimers();
      jest.restoreAllMocks();
      setIsAppFocused(true);
      jest.useRealTimers();
    });

    it('skips unknown and zero balances for initial, periodic and explicit polls', async () => {
      await activate();
      expect(chainUtils.getChainConfig('ton').foreignStakingTokenAddresses).toEqual([TONSTAKERS_JETTON]);
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      const { pollForeignStakingPromotion } = await import('./polling');
      expectForeignPolls(0);

      pollForeignStakingPromotion();
      await jest.advanceTimersByTimeAsync(30 * MINUTE);
      expectForeignPolls(0);

      emitBalances({ [slug]: 0n });
      pollForeignStakingPromotion();
      await jest.advanceTimersByTimeAsync(30 * MINUTE);
      expectForeignPolls(0);

      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);
    });

    it('fetches on the first positive balance and non-zero changes, then clears locally at zero', async () => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      const position = [{ chain: 'ton', providers: [{
        name: 'tonstakers', amount: '1', amountNative: '1', apy: 3,
        provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
      }] }];
      mockCallBackendGet.mockResolvedValueOnce(position);
      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);
      expect(mockOnUpdate).toHaveBeenCalledWith(expect.objectContaining({
        type: 'updateAccountBanners', stakingBanners: [expect.objectContaining({ kind: 'foreignStaking' })],
      }));

      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);

      const pending = new Deferred<typeof position>();
      mockCallBackendGet.mockReturnValueOnce(pending.promise);
      emitBalances({ [slug]: 2n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);

      mockOnUpdate.mockClear();
      emitBalances({});
      expect(mockOnUpdate).toHaveBeenCalledWith(expect.objectContaining({
        type: 'updateAccountBanners', homeBanners: [], stakingBanners: [],
      }));
      pending.resolve(position);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);
      expect(mockOnUpdate.mock.calls.filter(([update]) => update.type === 'updateAccountBanners')).toHaveLength(1);
    });

    it('ignores unchanged amounts, unrelated tokens and other accounts', async () => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 10n });
      emitBalances({ [slug]: 10n, [TONCOIN.slug]: 1n, 'ton-other': 100n });
      emitBalances({ [slug]: 20n }, '1-mainnet');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);

      emitBalances({ [slug]: 10n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);
    });

    it('ignores chains without declared foreign staking tokens', async () => {
      await activate();
      expect(chainUtils.getChainConfig('tron').foreignStakingTokenAddresses).toBeUndefined();
      emitBalances({ [TRC20_USDT_MAINNET.slug]: 1n }, '0-mainnet', 'tron');
      emitBalances({ [TRC20_USDT_MAINNET.slug]: 2n }, '0-mainnet', 'tron');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(0);
    });

    it('keeps foreign staking banners while any declared chain balance is positive', async () => {
      await activate();
      const getChainConfig = chainUtils.getChainConfig;
      const tronConfig = {
        ...getChainConfig('tron'),
        foreignStakingTokenAddresses: [TRC20_USDT_MAINNET.tokenAddress],
      };
      jest.spyOn(chainUtils, 'getChainConfig').mockImplementation((chain) => (
        chain === 'tron' ? tronConfig : getChainConfig(chain)
      ));
      const tonSlug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      const tronSlug = buildTokenSlug('tron', TRC20_USDT_MAINNET.tokenAddress);
      const position = [{ chain: 'ton', providers: [{
        name: 'tonstakers', amount: '1', amountNative: '1', apy: 3,
        provider: 'ts', unstake: { builder: 'ts', tokenAddress: TONSTAKERS_JETTON, ownerAddress: 'wallet-address' },
      }] }];
      const callBackendGet = mockCallBackendGet.getMockImplementation()!;
      mockCallBackendGet.mockImplementation((path: string, ...args: unknown[]) => (
        path === '/staking/foreign' ? Promise.resolve(position) : callBackendGet(path, ...args)
      ));

      emitBalances({ [tonSlug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);
      expect(mockOnUpdate).toHaveBeenCalledWith(expect.objectContaining({
        type: 'updateAccountBanners', stakingBanners: [expect.objectContaining({ kind: 'foreignStaking' })],
      }));

      emitBalances({ [tronSlug]: 2n }, '0-mainnet', 'tron');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);

      emitBalances({ [tronSlug]: 3n }, '0-mainnet', 'tron');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(3);

      emitBalances({ [tonSlug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(3);

      mockOnUpdate.mockClear();
      const pending = new Deferred<typeof position>();
      mockCallBackendGet.mockReturnValueOnce(pending.promise);
      emitBalances({ [tronSlug]: 0n }, '0-mainnet', 'tron');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(4);

      pending.resolve(position);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(4);
      expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({
        type: 'updateAccountBanners', stakingBanners: [],
      }));
    });

    it('resets the observation on account switches and ignores the previous account', async () => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);

      await activate('1-mainnet');
      emitBalances({ [slug]: 2n }, '1-mainnet');
      emitBalances({ [slug]: 3n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);

      emitBalances({ [slug]: 3n }, '1-mainnet');
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(3);

      await activate();
      emitBalances({ [slug]: 10n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(4);
    });

    it('removes the balance trigger when polling stops', async () => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      const { destroyPolling } = await import('./polling');
      await destroyPolling();

      emitBalances({ [slug]: 2n });
      await jest.advanceTimersByTimeAsync(30 * MINUTE);
      expectForeignPolls(1);
    });

    it('coalesces changes during an in-flight request into one serial follow-up poll', async () => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);

      const pending = new Deferred<[]>();
      mockCallBackendGet.mockReturnValueOnce(pending.promise);
      emitBalances({ [slug]: 2n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);

      emitBalances({ [slug]: 3n });
      emitBalances({ [slug]: 4n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(2);

      pending.resolve([]);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(3);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(3);
    });

    it.each([
      ['0-testnet', 'mnemonic', false], ['0-mainnet', 'view', false], ['0-mainnet', 'mnemonic', true],
    ] as const)('ignores balances for %s %s (no extra features: %s)', async (accountId, type, noExtraFeatures) => {
      mockNoExtraFeatures = noExtraFeatures;
      mockAccount.mockResolvedValue({ type, byChain: { ton: { address: 'wallet-address' } } });
      await activate(accountId);
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 1n }, accountId);
      emitBalances({ [slug]: 2n }, accountId);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(0);
    });

    it.each([true, false])('uses a 15/30-minute foreign staking interval (focused: %s)', async (isFocused) => {
      await activate();
      const slug = buildTokenSlug('ton', TONSTAKERS_JETTON);
      emitBalances({ [slug]: 1n });
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(1);
      setIsAppFocused(isFocused);

      await jest.advanceTimersByTimeAsync(MINUTE - 1);
      expect(mockCallBackendPost).toHaveBeenCalledTimes(1);
      expectForeignPolls(1);

      await jest.advanceTimersByTimeAsync(14 * MINUTE - 1);
      expectForeignPolls(1);
      await jest.advanceTimersByTimeAsync(1);
      expectForeignPolls(isFocused ? 2 : 1);
      await jest.advanceTimersByTimeAsync(15 * MINUTE);
      expectForeignPolls(isFocused ? 3 : 2);
    });

    async function activate(accountId = '0-mainnet') {
      const { setActivePollingAccount } = await import('./polling');
      await setActivePollingAccount(accountId, {});
      await jest.advanceTimersByTimeAsync(0);
    }

    function emitBalances(balances: ApiBalanceBySlug, accountId = '0-mainnet', chain: ApiChain = 'ton') {
      mockSetupActivePolling.mock.lastCall![2]({ type: 'updateBalances', accountId, chain, balances });
    }

    function expectForeignPolls(count: number) {
      expect(mockCallBackendGet.mock.calls.filter(([path]) => path === '/staking/foreign')).toHaveLength(count);
    }
  });
});

async function pollAccount(
  accountId: string,
  type = 'mnemonic',
  exercise?: (poll: { config: () => Promise<unknown>; foreign: () => Promise<unknown> }) => Promise<void>,
  foreignFirst = false,
) {
  mockAccount.mockResolvedValue({ type, byChain: { ton: { address: 'wallet-address' } } });
  const {
    initPolling, destroyPolling, setActivePollingAccount, pollAccountConfig, pollForeignStakingPromotion,
  } = await import('./polling');
  let ready!: VoidFunction;
  const initialized = new Promise<void>((resolve) => {
    ready = resolve;
  });
  let config: ApiUpdateAccountConfig['accountConfig'] | undefined;
  const updates: ApiUpdateAccountBanners[] = [];
  initPolling((update) => {
    if (update.type === 'updateConfig') ready();
    if (update.type === 'updateAccountConfig') config = update.accountConfig;
    if (update.type === 'updateAccountBanners') updates.push(update);
  });
  await initialized;
  mockNoExtraFeatures = false;
  try {
    await setActivePollingAccount(accountId, {});
    const poll = {
      config: () => Promise.resolve(pollAccountConfig()),
      foreign: () => {
        mockSetupActivePolling.mock.lastCall![2]({
          type: 'updateBalances', accountId, chain: 'ton',
          balances: { [buildTokenSlug('ton', TONSTAKERS_JETTON)]: 1n },
        });
        return Promise.resolve(pollForeignStakingPromotion());
      },
    };
    if (foreignFirst) {
      await poll.foreign();
      await poll.config();
    } else {
      await poll.config();
      await poll.foreign();
    }
    await exercise?.(poll);
    return {
      config,
      banners: updates.at(-1)!,
      updates,
    };
  } finally {
    mockNoExtraFeatures = true;
    await destroyPolling();
  }
}
