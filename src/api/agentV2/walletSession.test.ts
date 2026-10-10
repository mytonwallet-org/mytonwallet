import type { AgentFeatureCapabilitiesResponseV2 } from './protocol/types';
import type { AgentV2SessionStorage } from './sessionStorage';
import type { AgentV2HostContextSnapshot } from './types';

import { APP_NAME } from '../../config';
import { getSupportedChains } from '../../util/chain';
import contractManifest from './generated/manifest.json';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { AgentV2WalletSession, createAgentV2WalletSession } from './walletSession';

const WALLET_SESSION_STORAGE_KEY = 'agentV2WalletSession';
const LEGACY_SESSION_ID = '11111111-1111-4111-8111-111111111111';
const CURRENT_SESSION_ID = '22222222-2222-4222-8222-222222222222';
const CHAIN_LISTS = [
  { name: 'runtime catalog', chains: [...getSupportedChains()] },
  { name: 'future networks', chains: ['ton', ...Array.from({ length: 64 }, (_, index) => `future-chain-${index}`)] },
];
const CHAIN_CONTEXT_CASES = (['classic', 'ios', 'android'] as const).flatMap((platform) => (
  CHAIN_LISTS.map((entry) => ({ ...entry, platform }))
));

describe('AgentV2WalletSession semantic capabilities', () => {
  beforeEach(() => sessionStorage.clear());

  it('uses declared UI support independently of the platform name and wallet authority', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.uiCapabilities = {
      ...hostUiCapabilities('android'),
      supportedActions: ['receive', 'stake'],
      supportsFollowups: true,
    };
    session.update(host);
    expect(session.buildContext().capabilities).toEqual({
      protocolVersion: 3,
      supportedActions: ['receive', 'stake'],
      features: ['followups'],
    });

    host.accounts[0].isViewOnly = true;
    session.update(host);
    expect(session.buildContext().capabilities.supportedActions).toEqual(['receive']);
    session.update({ ...host, uiCapabilities: { ...host.uiCapabilities, supportedActions: [] } });
    expect(session.buildContext().capabilities.supportedActions).toEqual([]);
  });

  it('rejects an incompatible host UI capability contract', () => {
    const session = new AgentV2WalletSession();
    expect(() => session.update({
      ...hostContext(), uiCapabilities: undefined,
    } as unknown as AgentV2HostContextSnapshot)).toThrow('Invalid Agent V2 host context');
  });

  it('uses the interface language without advertising a separate response language catalog', () => {
    const session = new AgentV2WalletSession();
    session.update(hostContext());

    const context = session.buildContext();
    expect(context.context.appName).toBe(APP_NAME);
    expect(context.context.lang).toBe('en');
    expect(context.capabilities).not.toHaveProperty('supportedResponseLanguages');
  });

  it('quarantines invalid optional catalog assets without losing wallet context', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    const validAsset = host.assetCatalog![0];
    const validSwapAsset = {
      slug: 'usdton',
      chain: 'ton',
      symbol: 'USDT',
      decimals: 6,
      priceUsd: '1',
    };
    host.assetCatalog = [
      validAsset,
      { slug: 'solana-invalid', chain: 'solana', symbol: '', decimals: 8 },
    ];
    host.swapAssetCatalog = [
      validSwapAsset,
      { slug: 'solana-invalid', chain: 'solana', symbol: '', decimals: 8 },
    ];

    session.update(host);

    expect(session.snapshot().host?.assetCatalog).toEqual([validAsset]);
    expect(session.snapshot().host?.swapAssetCatalog).toEqual([validSwapAsset]);
    expect(session.buildContext().walletContext).toMatchObject({
      mode: 'wallet',
      activeNetwork: 'ton',
    });
  });

  it('advertises only host-supplied built-in destinations and withdraws them on host changes', () => {
    const session = new AgentV2WalletSession();
    const builtinDapps = [{ name: 'Buy SOL via MoonPay',
      url: 'mtw://buy-with-card?chain=solana&provider=moonpay' }];
    session.update({ ...hostContext(), builtinDapps });
    expect(session.buildContext().capabilities.builtinDapps).toEqual(builtinDapps);
    session.update({ ...hostContext(), builtinDapps: [] });
    expect(session.buildContext().capabilities.builtinDapps).toBeUndefined();
  });

  it.each([
    ['classic', ['followups', 'walletDirectory', 'sendRecipientWithoutAsset']],
    ['ios', ['followups', 'walletDirectory', 'sendRecipientWithoutAsset']],
    ['android', ['followups']],
  ] as const)('advertises only the presentation features the %s host renders', (platform, features) => {
    const session = new AgentV2WalletSession();
    session.update({ ...hostContext(), platform, uiCapabilities: hostUiCapabilities(platform) });

    expect(session.buildContext().capabilities.features).toEqual(features);
  });

  it('advertises no presentation features without a wallet host', () => {
    const session = new AgentV2WalletSession();

    expect(session.buildContext().capabilities.features).toEqual([]);
  });

  it('admits wallet query and the client time zone once the server offers the pinned filter catalog', () => {
    const session = new AgentV2WalletSession();
    session.update({ ...hostContext(), timeZone: 'Europe/Berlin' });
    expect(session.isWalletQueryAvailable()).toBe(false);
    expect(session.buildContext().context).not.toHaveProperty('timeZone');
    expect(session.buildContext().capabilities.features).not.toContain('walletChainLookup');

    session.updateFeatureCapabilities(featureCapabilities());

    const { context, walletContext, capabilities } = session.buildContext();
    expect(session.isWalletQueryAvailable()).toBe(true);
    // The server may then read the account's public addresses to look them up on the blockchain
    expect(capabilities.features).toContain('walletChainLookup');
    expect(context.timeZone).toBe('Europe/Berlin');
    expect(context.permissions).toEqual({ agentConsentAccepted: true });
    expect(walletContext).not.toHaveProperty('allowedAccountScopes');
  });

  it.each(CHAIN_CONTEXT_CASES)('preserves the complete $name on $platform', ({ platform, chains }) => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.platform = platform;
    host.uiCapabilities = hostUiCapabilities(platform);
    host.client = platform === 'classic' ? 'web' : 'native';
    host.accounts[0].chains = [...chains];
    host.accounts[0].addresses = Object.fromEntries(chains.map((chain) => [chain, `${chain}-public-address`]));
    session.update(host);
    session.updateFeatureCapabilities(featureCapabilities());

    const { context, capabilities, walletContext } = session.buildContext();
    expect(context.activeWalletChains).toEqual(chains);
    expect(walletContext.mode).toBe('wallet');
    if (walletContext.mode !== 'wallet') throw new Error('Expected wallet context');
    expect(walletContext.activeAccount.chains).toEqual(chains);
    expect(capabilities.features.includes('walletDirectory')).toBe(platform !== 'android');
    if (platform !== 'android') {
      const directory = session.buildWalletDirectory('2026-08-20T00:00:00.000Z');
      expect(directory.accounts[0].chains).toEqual(chains);
      expect(directory.coverage).toEqual({ accountsRequested: 1, accountsIncluded: 1, rowsOmitted: 0 });
    }
  });

  it.each([
    ['classic', true],
    ['ios', true],
    ['android', false],
  ] as const)('advertises the complete wallet directory on %s', (platform, expected) => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.platform = platform;
    host.uiCapabilities = hostUiCapabilities(platform);
    host.client = platform === 'classic' ? 'web' : 'native';
    host.accounts.push({
      ...host.accounts[0],
      accountId: 'savings-account',
      label: 'Savings',
      state: 'stale',
    });
    session.update(host);

    expect(session.buildContext().capabilities.features.includes('walletDirectory')).toBe(expected);
    if (expected) {
      expect(session.buildWalletDirectory('2026-08-20T00:00:00.000Z')).toMatchObject({
        status: 'complete',
        coverage: { accountsRequested: 2, accountsIncluded: 2, rowsOmitted: 0 },
        accounts: [
          { label: 'Main', isCurrent: true, state: 'active' },
          { label: 'Savings', isCurrent: false, state: 'stale' },
        ],
      });
    }
  });

  it.each([
    ['missing label', undefined],
    ['unsafe label', 'Main\u202Eevil'],
  ])('withdraws the wallet directory for an incomplete %s', (_case, label) => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.accounts[0].label = label;
    session.update(host);

    expect(session.buildContext().capabilities.features).not.toContain('walletDirectory');
  });

  it('withdraws wallet query when the catalog digest does not match', () => {
    const session = new AgentV2WalletSession();
    session.update({ ...hostContext(), timeZone: 'Europe/Berlin' });
    session.updateFeatureCapabilities(featureCapabilities('0'.repeat(64)));

    expect(session.isWalletQueryAvailable()).toBe(false);
    expect(session.buildContext().context).not.toHaveProperty('timeZone');
  });

  it.each([
    ['classic', 'web', [
      'send', 'receive', 'stake', 'swap', 'openDapp',
    ], ['send', 'receive', 'stake', 'swap']],
    ['ios', 'native', [
      'send', 'receive', 'stake', 'swap', 'openDapp',
    ], ['send', 'receive', 'stake', 'swap']],
    ['android', 'native', [
      'send', 'receive', 'stake', 'swap', 'openDapp',
    ], ['send', 'receive', 'stake', 'swap']],
  ] as const)(
    'advertises the exact prepared-action matrix on %s',
    (platform, client, supportedActions, walletSupportedActions) => {
      const session = new AgentV2WalletSession();
      session.update({ ...hostContext(), platform, client, uiCapabilities: hostUiCapabilities(platform) });
      session.updateFeatureCapabilities(featureCapabilities());

      const { capabilities, walletContext } = session.buildContext();

      expect(capabilities.supportedActions).toEqual(supportedActions);
      expect(walletContext.mode).toBe('wallet');
      if (walletContext.mode !== 'wallet') throw new Error('Expected wallet context');
      expect(walletContext.activeAccount.supportedActions).toEqual(walletSupportedActions);
    },
  );

  it('keeps Classic and iOS wallet authority and action kinds in parity', () => {
    const classic = new AgentV2WalletSession();
    const ios = new AgentV2WalletSession();
    classic.update({
      ...hostContext(),
      platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
      client: 'web',
      swapAssetCatalog: swapAssetCatalog(),
    });
    ios.update({
      ...hostContext(),
      platform: 'ios', uiCapabilities: hostUiCapabilities('ios'),
      client: 'native',
      swapAssetCatalog: swapAssetCatalog(),
    });
    classic.updateFeatureCapabilities(featureCapabilities());
    ios.updateFeatureCapabilities(featureCapabilities());

    const classicContext = classic.buildContext();
    const iosContext = ios.buildContext();

    expect(iosContext.capabilities).toEqual(classicContext.capabilities);
    expect(ios.isWalletQueryAvailable()).toBe(classic.isWalletQueryAvailable());
    expect(iosContext.walletContext.mode).toBe('wallet');
    expect(classicContext.walletContext.mode).toBe('wallet');
    if (iosContext.walletContext.mode !== 'wallet' || classicContext.walletContext.mode !== 'wallet') {
      throw new Error('Expected wallet contexts');
    }
    expect(iosContext.walletContext.activeAccount.supportedActions).toEqual(
      classicContext.walletContext.activeAccount.supportedActions,
    );
  });

  it.each([
    ['classic', false, false, false, true],
    ['ios', false, false, false, true],
    ['android', false, false, false, true],
    ['classic', true, false, false, false],
    ['classic', false, true, false, false],
    ['classic', false, false, true, false],
  ] as const)('advertises staking from account policy on %s', (
    platform, isViewOnly, isTestnet, isStakingDisabled, expected,
  ) => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.platform = platform;
    host.uiCapabilities = hostUiCapabilities(platform);
    host.isTestnet = isTestnet;
    host.isStakingDisabled = isStakingDisabled;
    host.accounts[0].isViewOnly = isViewOnly;
    host.accounts[0].accountType = isViewOnly ? 'viewOnly' : 'regular';
    host.assetCatalog = [];
    session.update(host);
    const context = session.buildContext();
    expect(context.capabilities.supportedActions.includes('stake')).toBe(expected);
    expect(JSON.stringify(context)).not.toMatch(/stakingOffers|stakingYieldOffers|staking\.offer\.read/);
  });

  it.each([
    ['eligible Classic mainnet wallet', 'classic', false, 'regular', false, 2, true],
    ['eligible iOS mainnet wallet', 'ios', false, 'regular', false, 2, true],
    ['eligible Android mainnet wallet', 'android', false, 'regular', false, 2, true],
    ['testnet wallet', 'classic', true, 'regular', false, 2, false],
    ['Ledger wallet', 'classic', false, 'ledger', false, 2, false],
    ['view-only wallet', 'classic', false, 'viewOnly', true, 2, false],
    ['empty local catalog', 'classic', false, 'regular', false, 0, true],
  ] as const)(
    'advertises the Swap action only for an %s without a client preparation tool',
    (_name, platform, isTestnet, accountType, isViewOnly, catalogSize, expected) => {
      const session = new AgentV2WalletSession();
      const host = hostContext();
      host.platform = platform;
      host.uiCapabilities = hostUiCapabilities(platform);
      host.client = platform === 'classic' ? 'web' : 'native';
      host.isTestnet = isTestnet;
      host.accounts[0].accountType = accountType;
      host.accounts[0].isViewOnly = isViewOnly;
      host.swapAssetCatalog = swapAssetCatalog().slice(0, catalogSize);
      session.update(host);

      const { capabilities, walletContext } = session.buildContext();
      expect(capabilities.supportedActions.includes('swap')).toBe(expected);
      expect(walletContext.mode).toBe('wallet');
      if (walletContext.mode !== 'wallet') throw new Error('Expected wallet context');
      expect(walletContext.activeAccount.supportedActions.includes('swap')).toBe(expected);
    },
  );

  it.each([
    ['classic', 'web', ['send', 'receive', 'openDapp'], ['send', 'receive']],
    ['ios', 'native', ['send', 'receive', 'openDapp'], ['send', 'receive']],
    ['android', 'native', ['send', 'receive', 'openDapp'], ['send', 'receive']],
  ] as const)(
    'advertises supported view-only wallet actions on %s',
    (platform, client, supportedActions, walletSupportedActions) => {
      const session = new AgentV2WalletSession();
      const host = hostContext();
      host.platform = platform;
      host.uiCapabilities = hostUiCapabilities(platform);
      host.client = client;
      host.accounts[0].accountType = 'viewOnly';
      host.accounts[0].isViewOnly = true;
      session.update(host);
      session.updateFeatureCapabilities(featureCapabilities());

      const { capabilities, walletContext } = session.buildContext();

      expect(session.isWalletQueryAvailable()).toBe(true);
      expect(capabilities.supportedActions).toEqual(supportedActions);
      expect(walletContext.mode).toBe('wallet');
      if (walletContext.mode !== 'wallet') throw new Error('Expected wallet context');
      expect(walletContext.activeAccount.supportedActions).toEqual(walletSupportedActions);
    },
  );

  it('withdraws wallet capabilities when the active account is not active', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.accounts[0].state = 'deleted';
    session.update(host);

    const { capabilities, walletContext } = session.buildContext();

    expect(capabilities.features).not.toContain('walletDirectory');
    expect(capabilities.supportedActions).toEqual(['openDapp']);
    expect(walletContext.mode).toBe('wallet');
    if (walletContext.mode !== 'wallet') throw new Error('Expected wallet context');
    expect(walletContext.activeAccount).toMatchObject({ state: 'deleted', supportedActions: [] });
  });

  it('increments authority revision only when wallet authority changes', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    expect(session.update(host)).toMatchObject({
      hasAuthorityChanged: true,
      hasWalletContextChanged: true,
    });
    const revision = session.snapshot().revision;
    expect(session.update({ ...host, lang: 'ru' })).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(session.snapshot().revision).toBe(revision);
    expect(session.update({
      ...host,
      accounts: [{
        ...host.accounts[0],
        holdings: [{
          ...host.accounts[0].holdings[0],
          balance: '20',
        }],
      }],
    })).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(session.snapshot().revision).toBe(revision);
    expect(session.update({ ...host, activeNetwork: 'tron' })).toMatchObject({
      hasAuthorityChanged: true,
      hasWalletContextChanged: true,
    });
    expect(session.snapshot().revision).toBe(revision + 1);
  });

  it('tracks swap identity changes without changing wallet authority', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.isTestnet = false;
    host.swapAssetCatalog = swapAssetCatalog();
    session.update(host);
    const revision = session.snapshot().revision;

    const refreshedPrices = {
      ...host,
      swapAssetCatalog: host.swapAssetCatalog.map((asset, index) => (
        index === 0 ? { ...asset, priceUsd: '4' } : asset
      )),
    };
    expect(session.update(refreshedPrices)).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(session.snapshot().revision).toBe(revision);
    expect(session.update({
      ...refreshedPrices,
      swapAssetCatalog: refreshedPrices.swapAssetCatalog.map((asset, index) => (
        index === 0 ? { ...asset, decimals: 8 } : asset
      )),
    })).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(session.snapshot().revision).toBe(revision);
    expect(session.update({ ...host, isTestnet: true })).toMatchObject({
      hasAuthorityChanged: true,
      hasWalletContextChanged: true,
    });
    expect(session.snapshot().revision).toBe(revision + 1);
  });

  it('tracks staking policy changes without changing wallet authority', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    session.update(host);
    const revision = session.snapshot().revision;

    expect(session.update({
      ...host,
      isStakingDisabled: true,
    })).toEqual({
      hasAuthorityChanged: false,
      hasWalletContextChanged: false,
    });
    expect(session.snapshot().revision).toBe(revision);
  });

  it('distinguishes account access changes from profile changes', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    const secondary = {
      ...host.accounts[0],
      accountId: 'secondary-account',
      label: 'Savings',
      addresses: { ton: 'EQ-secondary-address' },
    };
    session.update({ ...host, accounts: [...host.accounts, secondary] });
    const initialRevision = session.snapshot().revision;

    expect(session.update({ ...host, accounts: host.accounts })).toMatchObject({
      hasAuthorityChanged: true,
      hasWalletContextChanged: true,
    });
    expect(session.snapshot().revision).toBe(initialRevision + 1);

    session.update({ ...host, accounts: [...host.accounts, secondary] });
    const restoredRevision = session.snapshot().revision;
    expect(session.update({
      ...host,
      accounts: [...host.accounts, {
        ...secondary,
        label: 'Cold Savings',
        savedAddresses: [{
          id: 'treasury', name: 'Treasury', chain: 'ton', address: 'EQ-private-treasury',
        }],
      }],
    })).toMatchObject({
      hasAuthorityChanged: false,
      hasWalletContextChanged: true,
    });
    expect(session.snapshot().revision).toBe(restoredRevision + 1);
  });

  it('reuses an immutable authority binding across price and UI policy updates', async () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    session.update(host);
    const initial = await session.walletAuthorityBinding();
    expect(Object.isFrozen(initial)).toBe(true);
    expect(await session.walletAuthorityBinding()).toBe(initial);
    session.update({
      ...host,
      isStakingDisabled: true,
      accounts: host.accounts.map((account) => ({
        ...account,
        holdings: account.holdings.map((holding) => ({ ...holding, balance: '42' })),
      })),
    });
    expect(await session.walletAuthorityBinding()).toBe(initial);

    session.update({ ...host, accounts: [{ ...host.accounts[0], label: 'Renamed' }] });
    const renamed = await session.walletAuthorityBinding();
    expect(renamed).not.toBe(initial);
    expect(renamed.accountDigest).toBe(initial.accountDigest);
    expect(renamed.profileDigest).not.toBe(initial.profileDigest);
    expect(renamed.revision).toBe(initial.revision + 1);
  });

  it('converges an in-flight binding on the new session after reset', async () => {
    const session = new AgentV2WalletSession();
    session.update(hostContext());
    const originalSessionId = session.snapshot().sessionId;
    const pending = session.walletAuthorityBinding();
    await session.reset();
    const current = await session.walletAuthorityBinding();
    expect(current.sessionId).not.toBe(originalSessionId);
    expect(current.revision).toBe(0);
    await expect(pending).resolves.toBe(current);
  });

  it('converges authority binding when a secondary account changes during hashing', async () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.accounts.push({
      ...host.accounts[0],
      accountId: 'secondary-account',
      label: 'Savings',
      addresses: { ton: 'EQ-secondary-address' },
    });
    session.update(host);

    const bindingDuringUpdate = session.walletAuthorityBinding();
    session.update({ ...host, accounts: host.accounts.slice(0, 1) });

    await expect(bindingDuringUpdate).resolves.toEqual(await session.walletAuthorityBinding());
  });

  it('binds account eligibility and saved-contact profile changes', async () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    session.update(host);
    const initial = await session.walletAuthorityBinding();

    session.update({
      ...host,
      accounts: [{
        ...host.accounts[0],
        isViewOnly: true,
        label: 'Renamed',
        savedAddresses: [{
          id: 'treasury', name: 'Treasury', chain: 'ton', address: 'EQ-private-treasury',
        }],
      }],
    });
    const changed = await session.walletAuthorityBinding();

    expect(changed.accountDigest).not.toBe(initial.accountDigest);
    expect(changed.profileDigest).not.toBe(initial.profileDigest);
  });

  it('rotates a legacy persisted wallet session without deleting identity or consent records', async () => {
    sessionStorage.setItem(WALLET_SESSION_STORAGE_KEY, JSON.stringify({
      version: 1,
      sessionId: LEGACY_SESSION_ID,
      revision: 9,
      authorityFingerprint: 'legacy-authority',
    }));
    sessionStorage.setItem('agentV2Consent', 'preserve-consent');
    sessionStorage.setItem('agentV2DeviceIdentity', 'preserve-device');

    const session = await createAgentV2WalletSession();
    const persisted = JSON.parse(sessionStorage.getItem(WALLET_SESSION_STORAGE_KEY)!) as {
      version: number;
      sessionId: string;
      revision: number;
      authorityFingerprint: string;
    };

    expect(session.snapshot()).toMatchObject({ sessionId: persisted.sessionId, revision: 0 });
    expect(persisted).toMatchObject({ version: 2, revision: 0, authorityFingerprint: 'none' });
    expect(persisted.sessionId).not.toBe(LEGACY_SESSION_ID);
    expect(sessionStorage.getItem('agentV2Consent')).toBe('preserve-consent');
    expect(sessionStorage.getItem('agentV2DeviceIdentity')).toBe('preserve-device');
  });

  it('restores a valid current wallet-session record', async () => {
    sessionStorage.setItem(WALLET_SESSION_STORAGE_KEY, JSON.stringify({
      version: 2,
      sessionId: CURRENT_SESSION_ID,
      revision: 4,
      authorityFingerprint: 'current-authority',
    }));

    const session = await createAgentV2WalletSession();

    expect(session.snapshot()).toMatchObject({ sessionId: CURRENT_SESSION_ID, revision: 4 });
    expect(JSON.parse(sessionStorage.getItem(WALLET_SESSION_STORAGE_KEY)!)).toEqual({
      version: 2,
      sessionId: CURRENT_SESSION_ID,
      revision: 4,
      authorityFingerprint: 'current-authority',
    });
  });

  it('resets only wallet protocol session state', async () => {
    const session = await createAgentV2WalletSession();
    const previousSessionId = session.snapshot().sessionId;
    sessionStorage.setItem('agentV2Consent', 'preserve-consent');
    sessionStorage.setItem('agentV2DeviceIdentity', 'preserve-device');

    await session.reset();

    expect(session.snapshot()).toMatchObject({ revision: 0 });
    expect(session.snapshot().sessionId).not.toBe(previousSessionId);
    expect(sessionStorage.getItem(WALLET_SESSION_STORAGE_KEY)).not.toBeNull();
    expect(sessionStorage.getItem('agentV2Consent')).toBe('preserve-consent');
    expect(sessionStorage.getItem('agentV2DeviceIdentity')).toBe('preserve-device');
  });

  it('serializes session writes and waits for the latest state to persist', async () => {
    const firstWrite = createDeferred<void>();
    const persistedValues: Array<{ revision: number }> = [];
    const persistence: AgentV2SessionStorage = {
      getItem: () => Promise.resolve(sessionStorage.getItem('missing-agent-v2-session')),
      setItem: jest.fn((_key, value) => {
        persistedValues.push(JSON.parse(value) as { revision: number });
        return persistedValues.length === 1 ? firstWrite.promise : Promise.resolve();
      }),
      removeItem: jest.fn(() => Promise.resolve()),
    };
    const session = new AgentV2WalletSession({
      persistence,
      randomUuid: () => CURRENT_SESSION_ID,
    });

    session.update(hostContext());
    session.update({ ...hostContext(), activeNetwork: 'tron' });
    const flush = session.flushPersistence();
    await Promise.resolve();

    expect(persistedValues.map(({ revision }) => revision)).toEqual([0]);
    firstWrite.resolve();
    await flush;
    expect(persistedValues.map(({ revision }) => revision)).toEqual([0, 1, 2]);
  });

  it('keeps a fresh session usable when persistence is unavailable', async () => {
    const persistence: AgentV2SessionStorage = {
      getItem: jest.fn(() => Promise.reject(new Error('Session storage is unavailable'))),
      setItem: jest.fn(() => Promise.reject(new Error('Session storage is unavailable'))),
      removeItem: jest.fn(() => Promise.reject(new Error('Session storage is unavailable'))),
    };

    const session = await createAgentV2WalletSession({
      persistence,
      randomUuid: () => CURRENT_SESSION_ID,
    });
    session.update(hostContext());

    expect(session.snapshot()).toMatchObject({ sessionId: CURRENT_SESSION_ID, revision: 1 });
    expect(persistence.setItem).not.toHaveBeenCalled();
  });

  it('removes the persisted wallet session during a full reset', async () => {
    const persistence: AgentV2SessionStorage = {
      getItem: jest.fn(() => Promise.resolve(JSON.stringify({
        version: 2,
        sessionId: CURRENT_SESSION_ID,
        revision: 4,
        authorityFingerprint: 'current-authority',
      }))),
      setItem: jest.fn(() => Promise.resolve()),
      removeItem: jest.fn(() => Promise.resolve()),
    };
    const session = await createAgentV2WalletSession({ persistence });

    await session.reset({ shouldClearPersistentState: true });

    expect(persistence.removeItem).toHaveBeenCalledWith(WALLET_SESSION_STORAGE_KEY);
  });

  it('indexes account-bound contact and address references', () => {
    const session = new AgentV2WalletSession();
    const host = hostContext();
    host.accounts[0].savedAddresses = [{
      id: 'treasury', name: 'Treasury', chain: 'ton', address: 'EQ-private-treasury',
    }];

    session.update(host);

    const refs = session.resolveSavedAddressRefs('account-id', 'treasury');
    expect(refs).toEqual({
      contactRef: expect.stringMatching(/^contact_/u),
      addressRef: expect.stringMatching(/^address_/u),
    });
    expect(session.snapshot().addresses.get(refs!.addressRef)).toBe('EQ-private-treasury');
  });

  it('indexes opaque recipient references for own wallet addresses', () => {
    const session = new AgentV2WalletSession();
    session.update(hostContext());

    const refs = session.resolveWalletAddressRefs('account-id', 'ton');

    expect(refs).toEqual({
      contactRef: expect.stringMatching(/^contact_/u),
      addressRef: expect.stringMatching(/^address_/u),
    });
    expect(session.snapshot().addresses.get(refs!.addressRef)).toBe('EQ-public-address');
  });
});

function featureCapabilities(
  digest = contractManifest.walletFilterCatalogSha256,
): AgentFeatureCapabilitiesResponseV2 {
  return {
    protocolVersion: 3,
    walletQuery: {
      status: 'available',
      filterCatalog: { version: 1, digest, requiresClientTimeZone: true },
    },
    problemReport: { status: 'available' },
  };
}

function hostContext(): AgentV2HostContextSnapshot {
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'),
    client: 'web',
    lang: 'en',
    baseCurrency: 'USD',
    currencyRate: '1',
    activeAccountId: 'account-id',
    activeNetwork: 'ton',
    isTestnet: false,
    assetCatalog: [{
      slug: 'toncoin',
      chain: 'ton',
      symbol: 'TON',
      decimals: 9,
      priceUsd: '3',
      percentChange24h: '1.5',
    }],
    accounts: [{
      accountId: 'account-id',
      label: 'Main',
      state: 'active',
      accountType: 'regular',
      isViewOnly: false,
      chains: ['ton', 'tron'],
      addresses: { ton: 'EQ-public-address', tron: 'T-public-address' },
      holdings: [{
        asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '10',
      }],
    }],
    savedAddresses: [],
  };
}

function swapAssetCatalog(): NonNullable<AgentV2HostContextSnapshot['swapAssetCatalog']> {
  return [
    { slug: 'toncoin', chain: 'ton', symbol: 'TON', name: 'Toncoin', decimals: 9, priceUsd: '3' },
    { slug: 'usdton', chain: 'ton', symbol: 'USDT', name: 'Tether USD', decimals: 6, priceUsd: '1' },
  ];
}

function createDeferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}
