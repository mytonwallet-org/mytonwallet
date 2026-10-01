import type {
  AgentAssetIdentityV2,
  AgentCapabilities,
  AgentContext,
  AgentPortfolioPositionsFeatureStatusV1,
  AgentStakingCatalogFeatureStatusV1,
  AgentStakingOfferFeatureStatusV1,
  AgentToolCapability,
  AgentWalletContextV2,
  AgentWalletDirectoryResultV1,
  AgentWalletQueryFeatureStatusV1,
} from './protocol/types';
import type { AgentV2SessionStorage } from './sessionStorage';
import type {
  AgentV2HostAccount,
  AgentV2HostContextSnapshot,
  ApiUpdateAgentV2PortfolioHistory,
} from './types';

import { APP_NAME } from '../../config';
import { areSortedArraysEqual } from '../../util/iteratees';
import { sha256 } from '../common/utils';
import contractManifest from './generated/manifest.json';
import { AGENT_V2_TOOL_CONTRACTS } from './protocol/toolContractCatalog';
import {
  supportsAgentV2StakingAction,
  supportsAgentV2SwapAction,
} from './actionPlatformPolicy';
import sessionStorageAdapter from './sessionStorage';

const ALL_EVENTS = [
  'run_start',
  'thread',
  'message_start',
  'text_delta',
  'tool_call',
  'tool_status',
  'run_activity',
  'action',
  'followups',
  'input_continuations',
  'semantic_content',
  'message_content_end',
  'message_end',
  'rate_limit',
  'error',
] as const;
const MAX_HOST_ACCOUNTS = 100;
const MAX_HOST_ASSETS = 10_000;
const PORTFOLIO_HISTORY_RANGE_KEYS = {
  '1D': '1d',
  '7D': '7d',
  '1M': '1m',
  '3M': '3m',
  '1Y': '1y',
  ALL: 'all',
} as const;
const WALLET_SESSION_STORAGE_KEY = 'agentV2WalletSession';
const WALLET_SESSION_STORAGE_VERSION = 2;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const SAFE_STAKING_PRODUCT_ID_PATTERN = /^[A-Za-z0-9._:-]{1,64}$/u;
const STAKING_ANNUAL_YIELD_PATTERN
  = /^(?:(?:0|[1-9][0-9]{0,4})(?:\.[0-9]+)?|100000(?:\.0+)?)$/u;
const ACCOUNT_TYPES = new Set<AgentV2HostAccount['accountType']>([
  'regular',
  'ledger',
  'viewOnly',
  'multisig',
  'unknown',
]);

// Marked pure so a build without Agent V2 can drop the module
const TOOL_CAPABILITIES: AgentToolCapability[] = /* @__PURE__ */ AGENT_V2_TOOL_CONTRACTS.map(({
  name, version, scopes, timeoutMs, maxResultBytes,
}) => ({ name, version, scopes, timeoutMs, maxResultBytes }));

export interface AgentV2WalletSessionSnapshot {
  sessionId: string;
  revision: number;
  host?: AgentV2HostContextSnapshot;
  accountRefs: ReadonlyMap<string, string>;
  accountIds: ReadonlyMap<string, string>;
  addressRefs: ReadonlyMap<string, string>;
  addresses: ReadonlyMap<string, string>;
}

export interface AgentV2WalletSessionUpdate {
  hasAuthorityChanged: boolean;
  hasWalletContextChanged: boolean;
  hasActionPolicyChanged: boolean;
}

interface AgentV2AssetRefBinding {
  accountId: string;
  slug: string;
  chain: string;
}

interface PersistedWalletSession {
  authorityFingerprint: string;
  revision: number;
  sessionId: string;
}

interface AgentV2WalletSessionOptions {
  persistence?: AgentV2SessionStorage;
  persistedValue?: string | null;
  randomUuid?: () => string;
}

export async function createAgentV2WalletSession(options: {
  persistence?: AgentV2SessionStorage;
  randomUuid?: () => string;
} = {}) {
  const persistence = options.persistence ?? sessionStorageAdapter;
  let persistedValue: string | null;
  try {
    persistedValue = await persistence.getItem(WALLET_SESSION_STORAGE_KEY);
  } catch {
    return new AgentV2WalletSession({ randomUuid: options.randomUuid });
  }
  const session = new AgentV2WalletSession({
    persistence,
    persistedValue,
    randomUuid: options.randomUuid,
  });
  await session.flushPersistence();
  return session;
}

export class AgentV2WalletSession {
  private sessionId: string;
  private revision: number;
  private host?: AgentV2HostContextSnapshot;
  private authorityFingerprint: string;
  private queryAuthorityFingerprint?: string;
  private actionPolicyFingerprint?: string;
  private authorityGeneration = 0;
  private portfolioPositionsStatus: AgentPortfolioPositionsFeatureStatusV1 = 'disabled';
  private stakingOfferStatus: AgentStakingOfferFeatureStatusV1 = 'disabled';
  private stakingCatalogStatus: AgentStakingCatalogFeatureStatusV1 = 'disabled';
  private walletQueryStatus: AgentWalletQueryFeatureStatusV1 = 'disabled';
  private walletQueryVersions = new Set<AgentToolCapability['version']>();
  private walletQueryAdvertisedVersions: 5[] = [];
  private walletFilterCatalogDigest?: string;
  private readonly accountRefs = new Map<string, string>();
  private readonly accountIds = new Map<string, string>();
  private readonly addressRefs = new Map<string, string>();
  private readonly addresses = new Map<string, string>();
  private readonly contactRefs = new Map<string, string>();
  private readonly assetRefs = new Map<string, string>();
  private readonly assetBindings = new Map<string, AgentV2AssetRefBinding>();
  private readonly persistence?: AgentV2SessionStorage;
  private readonly randomUuid: () => string;
  private persistenceQueue = Promise.resolve();

  constructor(options: AgentV2WalletSessionOptions = {}) {
    const restored = parsePersistedWalletSession(options.persistedValue);
    this.randomUuid = options.randomUuid ?? (() => crypto.randomUUID());
    this.sessionId = restored?.sessionId ?? this.randomUuid();
    this.revision = restored?.revision ?? 0;
    this.authorityFingerprint = restored?.authorityFingerprint ?? 'none';
    this.persistence = options.persistence;
    this.persist();
  }

  update(snapshot?: AgentV2HostContextSnapshot): AgentV2WalletSessionUpdate {
    validateHostContext(snapshot);
    const nextSnapshot = mergePortfolioHistory(this.host, snapshot);
    const nextAuthorityFingerprint = buildAuthorityFingerprint(nextSnapshot);
    const nextQueryAuthorityFingerprint = JSON.stringify(queryAuthorityProjection(nextSnapshot));
    const nextActionPolicyFingerprint = buildActionPolicyFingerprint(nextSnapshot);
    const hasAuthorityChanged = nextAuthorityFingerprint !== this.authorityFingerprint;
    const hasQueryAuthorityChanged = this.queryAuthorityFingerprint !== undefined
      && nextQueryAuthorityFingerprint !== this.queryAuthorityFingerprint;
    const hasActionPolicyChanged = this.actionPolicyFingerprint !== undefined
      && nextActionPolicyFingerprint !== this.actionPolicyFingerprint;
    const hasWalletContextChanged = hasAuthorityChanged || hasQueryAuthorityChanged;
    if (hasWalletContextChanged) this.revision += 1;
    this.authorityFingerprint = nextAuthorityFingerprint;
    this.queryAuthorityFingerprint = nextQueryAuthorityFingerprint;
    this.actionPolicyFingerprint = nextActionPolicyFingerprint;
    this.host = nextSnapshot;
    this.authorityGeneration += 1;
    if (nextSnapshot) this.index(nextSnapshot);
    this.refreshWalletQueryVersions();
    this.persist();
    return { hasAuthorityChanged, hasWalletContextChanged, hasActionPolicyChanged };
  }

  rememberPortfolioHistory(update: Omit<ApiUpdateAgentV2PortfolioHistory, 'type'>) {
    const range = PORTFOLIO_HISTORY_RANGE_KEYS[update.range];
    if (
      !this.host
      || update.accountId !== this.host.activeAccountId
      || update.baseCurrency !== this.host.baseCurrency
    ) return;

    this.host = {
      ...this.host,
      portfolioHistory: {
        ...this.host.portfolioHistory,
        [range]: {
          response: update.netWorth,
          fetchedAtSlot: update.fetchedAtSlot,
        },
      },
    };
  }

  updateFeatureCapabilities(
    portfolioPositions?: AgentPortfolioPositionsFeatureStatusV1,
    walletQuery?: AgentWalletQueryFeatureStatusV1,
    stakingOffer?: AgentStakingOfferFeatureStatusV1,
    stakingCatalog?: AgentStakingCatalogFeatureStatusV1,
  ) {
    this.portfolioPositionsStatus = portfolioPositions ?? 'disabled';
    this.walletQueryStatus = walletQuery ?? 'disabled';
    this.stakingOfferStatus = stakingOffer ?? 'disabled';
    this.stakingCatalogStatus = stakingCatalog ?? 'disabled';
  }

  updateWalletQueryCapabilities(capabilities?: {
    status: 'available' | 'disabled';
    supportedToolVersions: 5[];
    filterCatalog?: { version: 1; digest: string; requiresClientTimeZone: true };
  }) {
    this.walletQueryAdvertisedVersions = capabilities?.status === 'available'
      ? capabilities.supportedToolVersions
      : [];
    this.walletFilterCatalogDigest = capabilities?.filterCatalog?.digest;
    this.refreshWalletQueryVersions();
  }

  async reset({ shouldClearPersistentState = false }: { shouldClearPersistentState?: boolean } = {}) {
    this.sessionId = this.randomUuid();
    this.revision = 0;
    this.host = undefined;
    this.authorityFingerprint = 'none';
    this.queryAuthorityFingerprint = undefined;
    this.actionPolicyFingerprint = undefined;
    this.authorityGeneration += 1;
    this.portfolioPositionsStatus = 'disabled';
    this.stakingOfferStatus = 'disabled';
    this.stakingCatalogStatus = 'disabled';
    this.walletQueryStatus = 'disabled';
    this.walletQueryVersions = new Set();
    this.walletQueryAdvertisedVersions = [];
    this.walletFilterCatalogDigest = undefined;
    this.accountRefs.clear();
    this.accountIds.clear();
    this.addressRefs.clear();
    this.addresses.clear();
    this.contactRefs.clear();
    this.assetRefs.clear();
    this.assetBindings.clear();
    if (shouldClearPersistentState) {
      this.enqueuePersistence((persistence) => persistence.removeItem(WALLET_SESSION_STORAGE_KEY));
    } else {
      this.persist();
    }
    await this.flushPersistence();
  }

  async flushPersistence() {
    await this.persistenceQueue;
  }

  snapshot(): AgentV2WalletSessionSnapshot {
    return {
      sessionId: this.sessionId,
      revision: this.revision,
      host: this.host,
      accountRefs: this.accountRefs,
      accountIds: this.accountIds,
      addressRefs: this.addressRefs,
      addresses: this.addresses,
    };
  }

  buildContext(): {
    context: AgentContext;
    capabilities: AgentCapabilities;
    walletContext: AgentWalletContextV2;
  } {
    const host = this.host;
    const activeAccount = host ? findActiveAccount(host) : undefined;
    const isRichPresentationSupported = host?.platform === 'ios' || host?.platform === 'android';
    const isPreparedSendPresentationSupported = host?.platform === 'classic' || isRichPresentationSupported;
    const isFollowupPresentationSupported = host?.platform === 'classic' || host?.platform === 'ios';
    const supportsSemanticContent = host?.platform === 'classic' || host?.platform === 'ios';
    const isNavigationSupported = host?.platform === 'classic' || host?.platform === 'ios';
    const isPortfolioPositionsSupported = supportsSemanticContent
      && this.portfolioPositionsStatus === 'available';
    const isWalletQuerySupported = supportsSemanticContent && this.walletQueryStatus === 'available';
    const isWalletDirectorySupported = Boolean(
      (host?.platform === 'classic' || host?.platform === 'ios')
      && host
      && canBuildWalletDirectory(host),
    );
    const isInputContinuationsSupported = host?.platform !== 'android';
    const isMarketQuoteSupported = Boolean(
      supportsSemanticContent
      && isInputContinuationsSupported
      && host?.currencyRate
      && host.assetCatalog?.some((asset) => (
        asset.priceUsd !== undefined && asset.percentChange24h !== undefined
      )),
    );
    const isStakingOfferSupported = Boolean(
      this.stakingOfferStatus === 'available'
      && host?.isTestnet === false
      && host.stakingOffers?.some((offer) => (
        host.assetCatalog?.some((asset) => areAssetIdentitiesEqual(asset, offer.asset))
      )),
    );
    const isStakingCatalogSupported = Boolean(
      supportsSemanticContent
      && this.stakingCatalogStatus === 'available'
      && host?.isTestnet === false,
    );
    const isActiveAccountAvailable = activeAccount?.state === 'active';
    const canPresentPreparedSend = isPreparedSendPresentationSupported
      && isActiveAccountAvailable
      && activeAccount.isViewOnly === false;
    const canOpenStaking = supportsAgentV2StakingAction(host?.platform)
      && isActiveAccountAvailable
      && activeAccount.isViewOnly === false
      && Boolean(host?.stakingOffers?.some(({ availability }) => availability === 'available'));
    const stakingYieldOffers = isStakingOfferSupported
      ? host!.stakingOffers!
        .filter((offer) => host!.assetCatalog!.some((asset) => areAssetIdentitiesEqual(asset, offer.asset)))
        .map(({ productId, asset }) => ({
          productId,
          asset: projectStakingAssetIdentity(asset),
        }))
      : [];
    const canPrepareSwap = supportsAgentV2SwapAction(host?.platform)
      && isActiveAccountAvailable
      && activeAccount.isViewOnly === false
      && activeAccount.accountType !== 'ledger'
      && host.isTestnet === false
      && (host.swapAssetCatalog?.length ?? 0) >= 2;
    const supportedTools = isActiveAccountAvailable
      ? TOOL_CAPABILITIES.filter(({ name, version }) => (
        name === 'action.send.prepare'
          ? version === 1 && canPresentPreparedSend
          : name === 'action.swap.prepare'
            ? version === 1 && canPrepareSwap
            : name === 'wallet.data.query'
              ? version === 5 && isWalletQuerySupported && this.walletQueryVersions.has(version)
              : name === 'wallet.directory.query'
                ? version === 1 && isWalletDirectorySupported
                : name === 'market.asset.quote'
                  ? version === 1 && isMarketQuoteSupported
                  : name === 'staking.offer.read'
                    ? version === 1 && isStakingOfferSupported
                    : name === 'staking.offers.list'
                      ? version === 1 && isStakingCatalogSupported
                      : false
      ))
      : [];
    const walletSupportedActions = isActiveAccountAvailable
      ? [
        ...(canPresentPreparedSend ? ['send' as const] : []),
        ...(isPreparedSendPresentationSupported ? ['receive' as const] : []),
        ...(canOpenStaking ? ['stake' as const] : []),
        ...(canPrepareSwap ? ['swap' as const] : []),
      ]
      : [];
    const supportedActions = [
      ...(isActiveAccountAvailable ? [
        ...walletSupportedActions,
        ...(isPortfolioPositionsSupported ? ['hideSpamAssets' as const] : []),
      ] : []),
      ...(isNavigationSupported ? [
        'openUrl' as const,
        'openToken' as const,
        'openTransaction' as const,
        'openAgent' as const,
      ] : []),
    ];
    const supportedEventTypes = ALL_EVENTS.filter((type) => (
      (type !== 'followups' || isFollowupPresentationSupported)
      && (type !== 'input_continuations' || isInputContinuationsSupported)
    ));

    const context: AgentContext = {
      platform: host?.platform ?? 'classic',
      client: host?.client ?? 'web',
      lang: host?.lang ?? 'en',
      baseCurrency: host?.baseCurrency ?? 'USD',
      ...(APP_NAME === 'My Wallet' || APP_NAME === 'Gram Wallet' ? { appName: APP_NAME } : {}),
      ...(isWalletQuerySupported && this.walletQueryVersions.has(5) && host?.timeZone && isValidTimeZone(host.timeZone)
        ? { timeZone: host.timeZone }
        : {}),
      ...(host?.appVersion ? { appVersion: host.appVersion } : {}),
      ...(host?.theme ? { theme: host.theme } : {}),
      ...(activeAccount ? { activeWalletChains: activeAccount.chains } : {}),
      permissions: {
        agentConsentAccepted: true,
      },
    };
    const capabilities: AgentCapabilities = {
      protocolVersion: 2,
      streamFormat: 'ndjson',
      supportedEventTypes,
      supportedTools,
      supportedActions,
      ...(walletSupportedActions.includes('receive') ? { receiveActionVersion: 3 as const } : {}),
      supportsFollowups: isFollowupPresentationSupported,
      supportsInputContinuations: isInputContinuationsSupported,
      supportsMessageEdit: host?.platform !== 'ios',
      supportsRegenerate: host?.platform === 'android',
    };
    const walletContext: AgentWalletContextV2 = !activeAccount || !host?.activeNetwork
      ? { mode: 'none', reason: 'noWallet' }
      : {
        mode: 'wallet',
        sessionId: this.sessionId,
        revision: this.revision,
        activeAccount: {
          accountRef: this.getAccountRef(activeAccount.accountId),
          state: activeAccount.state,
          isViewOnly: activeAccount.isViewOnly,
          chains: activeAccount.chains,
          supportedActions: walletSupportedActions,
          ...(stakingYieldOffers.length ? { stakingYieldOffers } : {}),
          ...(canOpenStaking ? {
            stakingOffers: host.stakingOffers!
              .filter(({ availability }) => availability === 'available')
              .map(({ productId, asset }) => ({
                productId,
                asset: projectStakingAssetIdentity(asset),
              })),
          } : {}),
        },
        activeNetwork: host.activeNetwork,
      };
    return { context, capabilities, walletContext };
  }

  buildWalletDirectory(generatedAt: string): AgentWalletDirectoryResultV1 {
    const host = this.host;
    const active = host ? findActiveAccount(host) : undefined;
    if (!host || !active || active.state !== 'active' || !canBuildWalletDirectory(host)) {
      throw new Error('Wallet directory is unavailable');
    }
    const accounts = host.accounts.filter(({ state }) => state !== 'deleted').map((account) => ({
      accountRef: this.getAccountRef(account.accountId),
      label: account.label!.trim(),
      isCurrent: account.accountId === host.activeAccountId,
      state: account.state as 'active' | 'stale',
      chains: [...account.chains],
    }));
    return {
      schemaVersion: 1,
      status: 'complete',
      generatedAt,
      coverage: {
        accountsRequested: accounts.length,
        accountsIncluded: accounts.length,
        rowsOmitted: 0,
      },
      sessionId: this.sessionId,
      revision: this.revision,
      accounts,
    };
  }

  private refreshWalletQueryVersions() {
    const v5Ready = Boolean(
      this.host?.platform !== 'android'
      && this.walletFilterCatalogDigest === contractManifest.walletFilterCatalogSha256,
    );
    this.walletQueryVersions = new Set(this.walletQueryAdvertisedVersions.filter(() => v5Ready));
  }

  private persist() {
    if (!this.persistence) return;
    const value = JSON.stringify({
      version: WALLET_SESSION_STORAGE_VERSION,
      sessionId: this.sessionId,
      revision: this.revision,
      authorityFingerprint: this.authorityFingerprint,
    });
    this.enqueuePersistence((persistence) => persistence.setItem(WALLET_SESSION_STORAGE_KEY, value));
  }

  private enqueuePersistence(operation: (persistence: AgentV2SessionStorage) => Promise<void>) {
    const persistence = this.persistence;
    if (!persistence) return;
    this.persistenceQueue = this.persistenceQueue
      .then(() => operation(persistence))
      .catch(() => undefined);
  }

  async walletBucketHash(): Promise<string | undefined> {
    const host = this.host;
    const active = host ? findActiveAccount(host) : undefined;
    if (!host || !active || active.isViewOnly) return undefined;
    const addresses = host.accounts.flatMap((account) => Object.values(account.addresses))
      .filter((address): address is string => Boolean(address))
      .sort();
    if (!addresses.length) return undefined;
    const digest = await sha256(new TextEncoder().encode(`agent-v2-wallet-bucket-v1\0${addresses.join('\0')}`));
    return toBase64Url(new Uint8Array(digest));
  }

  async walletAuthorityBinding() {
    while (true) {
      const generation = this.authorityGeneration;
      const host = this.host;
      const revision = this.revision;
      const sessionId = this.sessionId;
      const { accounts, profileAccounts, savedAddresses } = queryAuthorityProjection(host);
      const [accountDigest, profileDigest] = await Promise.all([
        sha256(new TextEncoder().encode(JSON.stringify({
          activeAccountId: host?.activeAccountId,
          activeNetwork: host?.activeNetwork,
          accounts,
        }))),
        sha256(new TextEncoder().encode(JSON.stringify({
          accounts: profileAccounts,
          savedAddresses,
        }))),
      ]);
      if (generation !== this.authorityGeneration) continue;
      return {
        accountDigest: toBase64Url(new Uint8Array(accountDigest)),
        profileDigest: toBase64Url(new Uint8Array(profileDigest)),
        revision,
        sessionId,
      };
    }
  }

  private index(snapshot: AgentV2HostContextSnapshot) {
    for (const account of snapshot.accounts) {
      this.getAccountRef(account.accountId);
      for (const [chain, address] of Object.entries(account.addresses)) {
        if (!address) continue;
        const key = walletAddressKey(account.accountId, chain);
        this.getAddressRef(key, address);
        this.getContactRef(key);
      }
      for (const holding of account.holdings) {
        this.getAssetRef(account.accountId, holding.asset.slug, holding.asset.chain);
      }
      for (const entry of account.savedAddresses ?? []) {
        const key = accountSavedAddressKey(account.accountId, entry.id);
        this.getAddressRef(key, entry.address);
        this.getContactRef(key);
      }
    }
    for (const entry of snapshot.savedAddresses) {
      this.getAddressRef(`saved:${entry.id}`, entry.address);
      this.getContactRef(entry.id);
    }
  }

  private getAccountRef(accountId: string) {
    let ref = this.accountRefs.get(accountId);
    if (!ref) {
      ref = `account_${crypto.randomUUID()}`;
      this.accountRefs.set(accountId, ref);
      this.accountIds.set(ref, accountId);
    }
    return ref;
  }

  private getAddressRef(key: string, address: string) {
    let ref = this.addressRefs.get(key);
    if (!ref) {
      ref = `address_${crypto.randomUUID()}`;
      this.addressRefs.set(key, ref);
    }
    this.addresses.set(ref, address);
    return ref;
  }

  private getContactRef(key: string) {
    let ref = this.contactRefs.get(key);
    if (!ref) {
      ref = `contact_${crypto.randomUUID()}`;
      this.contactRefs.set(key, ref);
    }
    return ref;
  }

  getAssetRef(accountId: string, slug: string, chain: string) {
    const key = `${accountId}\0${chain}\0${slug}`;
    let ref = this.assetRefs.get(key);
    if (!ref) {
      ref = `asset_${crypto.randomUUID()}`;
      this.assetRefs.set(key, ref);
    }
    this.assetBindings.set(ref, { accountId, slug, chain });
    return ref;
  }

  resolveAssetRef(assetRef: string) {
    return this.assetBindings.get(assetRef);
  }

  resolveSavedAddressRefs(accountId: string, contactId: string) {
    const key = accountSavedAddressKey(accountId, contactId);
    const contactRef = this.contactRefs.get(key);
    const addressRef = this.addressRefs.get(key);
    return contactRef && addressRef ? { contactRef, addressRef } : undefined;
  }

  resolveWalletAddressRefs(accountId: string, chain: string) {
    const key = walletAddressKey(accountId, chain);
    const contactRef = this.contactRefs.get(key);
    const addressRef = this.addressRefs.get(key);
    return contactRef && addressRef ? { contactRef, addressRef } : undefined;
  }
}

function findActiveAccount(snapshot: AgentV2HostContextSnapshot): AgentV2HostAccount | undefined {
  return snapshot.accounts.find(({ accountId }) => accountId === snapshot.activeAccountId);
}

function canBuildWalletDirectory(snapshot: AgentV2HostContextSnapshot): boolean {
  const accounts = snapshot.accounts.filter(({ state }) => state !== 'deleted');
  if (!accounts.length || accounts.length > MAX_HOST_ACCOUNTS) return false;
  return accounts.every(({ accountId, label, chains }) => {
    const value = label?.trim();
    return Boolean(
      accountId
      && value
      && Array.from(value).length <= 80
      && !hasUnsafeDirectoryLabelCharacters(value)
      && chains.length >= 1
      && chains.length <= 16
      && new Set(chains).size === chains.length,
    );
  });
}

function hasUnsafeDirectoryLabelCharacters(value: string): boolean {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0)!;
    return codePoint <= 0x1F
      || (codePoint >= 0x7F && codePoint <= 0x9F)
      || (codePoint >= 0x202A && codePoint <= 0x202E)
      || (codePoint >= 0x2066 && codePoint <= 0x2069);
  });
}

function accountSavedAddressKey(accountId: string, contactId: string) {
  return `account:${accountId}:saved:${contactId}`;
}

function walletAddressKey(accountId: string, chain: string) {
  return `wallet:${accountId}:${chain}`;
}

function queryAuthorityProjection(snapshot?: AgentV2HostContextSnapshot) {
  const accounts = (snapshot?.accounts ?? []).map((account) => ({
    accountId: account.accountId,
    accountType: account.accountType,
    chains: [...account.chains].sort(),
    isViewOnly: account.isViewOnly,
    state: account.state,
  })).sort((left, right) => left.accountId.localeCompare(right.accountId));
  const profileAccounts = (snapshot?.accounts ?? []).map((account) => ({
    accountId: account.accountId,
    addresses: Object.entries(account.addresses)
      .filter((entry): entry is [string, string] => Boolean(entry[1]))
      .sort(([left], [right]) => left.localeCompare(right)),
    label: account.label ?? '',
    portfolioWalletKeys: [...(account.portfolioWalletKeys ?? [])].sort(),
    savedAddresses: [...(account.savedAddresses ?? [])].map((entry) => ({
      address: entry.address,
      chain: entry.chain,
      id: entry.id,
      name: entry.name,
    })).sort((left, right) => left.id.localeCompare(right.id)),
  })).sort((left, right) => left.accountId.localeCompare(right.accountId));
  const savedAddresses = [...(snapshot?.savedAddresses ?? [])].map((entry) => ({
    address: entry.address,
    chain: entry.chain,
    id: entry.id,
    name: entry.name,
  })).sort((left, right) => left.id.localeCompare(right.id));
  return { accounts, profileAccounts, savedAddresses };
}

function mergePortfolioHistory(
  current: AgentV2HostContextSnapshot | undefined,
  next: AgentV2HostContextSnapshot | undefined,
): AgentV2HostContextSnapshot | undefined {
  if (
    !current?.portfolioHistory
    || !next
    || current.activeAccountId !== next.activeAccountId
    || current.baseCurrency !== next.baseCurrency
  ) return next;

  const currentWalletKeys = getActivePortfolioWalletKeys(current);
  const nextWalletKeys = getActivePortfolioWalletKeys(next);
  if (!areSortedArraysEqual(currentWalletKeys, nextWalletKeys)) {
    return { ...next, portfolioHistory: undefined };
  }

  return {
    ...next,
    portfolioHistory: {
      ...current.portfolioHistory,
      ...next.portfolioHistory,
    },
  };
}

function getActivePortfolioWalletKeys(snapshot: AgentV2HostContextSnapshot) {
  return [...new Set(findActiveAccount(snapshot)?.portfolioWalletKeys ?? [])].sort();
}

function buildAuthorityFingerprint(snapshot?: AgentV2HostContextSnapshot): string {
  if (!snapshot) return 'none';
  return JSON.stringify({
    activeAccountId: snapshot.activeAccountId,
    activeNetwork: snapshot.activeNetwork,
    accounts: snapshot.accounts.map((account) => ({
      accountId: account.accountId,
      accountType: account.accountType,
      addresses: Object.entries(account.addresses)
        .filter((entry): entry is [string, string] => Boolean(entry[1]))
        .sort(([left], [right]) => left.localeCompare(right)),
      state: account.state,
      isViewOnly: account.isViewOnly,
      chains: [...account.chains].sort(),
    })).sort((left, right) => left.accountId.localeCompare(right.accountId)),
    isTestnet: snapshot.isTestnet,
  });
}

function buildActionPolicyFingerprint(snapshot?: AgentV2HostContextSnapshot): string {
  return JSON.stringify({
    platform: snapshot?.platform,
    stakingOffers: snapshot?.stakingOffers,
    swapAssets: (snapshot?.swapAssetCatalog ?? []).map((asset) => ({
      slug: asset.slug,
      chain: asset.chain,
      symbol: asset.symbol,
      tokenAddress: asset.tokenAddress,
      decimals: asset.decimals,
    })).sort((left, right) => (
      left.chain.localeCompare(right.chain) || left.slug.localeCompare(right.slug)
    )),
  });
}

function validateHostContext(snapshot?: AgentV2HostContextSnapshot) {
  if (!snapshot) return;
  if (
    !Array.isArray(snapshot.accounts)
    || snapshot.accounts.length > MAX_HOST_ACCOUNTS
    || (snapshot.assetCatalog !== undefined && (
      !Array.isArray(snapshot.assetCatalog)
      || snapshot.assetCatalog.length > MAX_HOST_ASSETS
    ))
    || (snapshot.swapAssetCatalog !== undefined && (
      !Array.isArray(snapshot.swapAssetCatalog)
      || snapshot.swapAssetCatalog.length > MAX_HOST_ASSETS
    ))
    || (snapshot.isTestnet !== undefined && typeof snapshot.isTestnet !== 'boolean')
    || !Array.isArray(snapshot.savedAddresses)
    || (snapshot.stakingOffers !== undefined && (
      !Array.isArray(snapshot.stakingOffers)
      || snapshot.stakingOffers.length > 8
      || snapshot.stakingOffers.some((offer) => !isValidStakingOffer(offer))
    ))
  ) {
    throw new Error('Invalid Agent V2 host context');
  }
  for (const account of snapshot.accounts) {
    if (
      !account.accountId
      || !ACCOUNT_TYPES.has(account.accountType)
      || !Array.isArray(account.chains)
      || !Array.isArray(account.holdings)
      || (account.savedAddresses !== undefined && !Array.isArray(account.savedAddresses))
    ) {
      throw new Error('Invalid Agent V2 account context');
    }
  }
  for (const asset of snapshot.assetCatalog ?? []) {
    if (
      !asset.slug
      || !asset.chain
      || !asset.symbol
      || !Number.isInteger(asset.decimals)
      || asset.decimals < 0
      || (asset.priceUsd !== undefined && !isValidUnsignedDecimal(asset.priceUsd))
      || (asset.percentChange24h !== undefined && !isValidDecimal(asset.percentChange24h))
    ) {
      throw new Error('Invalid Agent V2 asset catalog');
    }
  }
  for (const asset of snapshot.swapAssetCatalog ?? []) {
    if (
      !asset.slug
      || !asset.chain
      || !asset.symbol
      || !Number.isInteger(asset.decimals)
      || asset.decimals < 0
      || (asset.priceUsd !== undefined && !isValidUnsignedDecimal(asset.priceUsd))
    ) {
      throw new Error('Invalid Agent V2 swap asset catalog');
    }
  }
}

function isValidStakingOffer(offer: NonNullable<AgentV2HostContextSnapshot['stakingOffers']>[number]) {
  return SAFE_STAKING_PRODUCT_ID_PATTERN.test(offer.productId)
    && (offer.yieldType === 'APY' || offer.yieldType === 'APR')
    && (offer.availability === 'available' || offer.availability === 'disabled')
    && offer.annualYield.length <= 128
    && STAKING_ANNUAL_YIELD_PATTERN.test(offer.annualYield)
    && isValidAssetIdentity(offer.asset);
}

function isValidAssetIdentity(asset: NonNullable<AgentV2HostContextSnapshot['stakingOffers']>[number]['asset']) {
  return asset.slug.length >= 1
    && asset.slug.length <= 128
    && asset.chain.length >= 1
    && asset.chain.length <= 32
    && asset.symbol.length >= 1
    && asset.symbol.length <= 32
    && (asset.name === undefined || (asset.name.length >= 1 && asset.name.length <= 160))
    && (asset.tokenAddress === undefined
      || (asset.tokenAddress.length >= 1 && asset.tokenAddress.length <= 256))
    && (asset.decimals === undefined
      || (Number.isInteger(asset.decimals) && asset.decimals >= 0 && asset.decimals <= 255));
}

function projectStakingAssetIdentity(
  asset: NonNullable<AgentV2HostContextSnapshot['stakingOffers']>[number]['asset'],
): AgentAssetIdentityV2 {
  return {
    slug: asset.slug,
    chain: asset.chain,
    symbol: asset.symbol,
    ...(asset.name ? { name: asset.name } : {}),
    ...(asset.tokenAddress ? { tokenAddress: asset.tokenAddress } : {}),
    ...(asset.decimals !== undefined ? { decimals: asset.decimals } : {}),
  };
}

function areAssetIdentitiesEqual(
  first: NonNullable<AgentV2HostContextSnapshot['assetCatalog']>[number],
  second: NonNullable<AgentV2HostContextSnapshot['stakingOffers']>[number]['asset'],
) {
  return first.slug === second.slug
    && first.chain === second.chain
    && first.symbol === second.symbol
    && first.name === second.name
    && first.tokenAddress === second.tokenAddress
    && first.decimals === second.decimals;
}

function isValidUnsignedDecimal(value: string | number) {
  return typeof value === 'number'
    ? Number.isFinite(value) && value >= 0
    : /^(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(value);
}

function isValidDecimal(value: string | number) {
  return typeof value === 'number'
    ? Number.isFinite(value)
    : /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(value);
}

function isValidTimeZone(value: string): boolean {
  if (!value || value.length > 64 || !/^[A-Za-z0-9_+./-]+$/u.test(value)) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format();
    return value === 'UTC' || value.includes('/');
  } catch {
    return false;
  }
}

function toBase64Url(bytes: Uint8Array) {
  let binary = '';
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/u, '');
}

function parsePersistedWalletSession(value?: string | null): PersistedWalletSession | undefined {
  try {
    const parsed = JSON.parse(value ?? 'null') as {
      version?: number;
      authorityFingerprint?: string;
      revision?: number;
      sessionId?: string;
    } | null;
    if (
      parsed?.version !== WALLET_SESSION_STORAGE_VERSION
      || typeof parsed.sessionId !== 'string'
      || !UUID_PATTERN.test(parsed.sessionId)
      || typeof parsed.revision !== 'number'
      || !Number.isSafeInteger(parsed.revision)
      || parsed.revision < 0
      || typeof parsed.authorityFingerprint !== 'string'
    ) return undefined;
    return {
      authorityFingerprint: parsed.authorityFingerprint,
      revision: parsed.revision,
      sessionId: parsed.sessionId,
    };
  } catch {
    return undefined;
  }
}

export async function clearPersistedAgentV2WalletSession(
  persistence: AgentV2SessionStorage = sessionStorageAdapter,
) {
  try {
    await persistence.removeItem(WALLET_SESSION_STORAGE_KEY);
  } catch {
    // Session storage is optional in embedded clients.
  }
}
