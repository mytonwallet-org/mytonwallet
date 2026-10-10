import type {
  AgentCapabilities,
  AgentClientFeature,
  AgentContext,
  AgentFeatureCapabilitiesResponseV2,
  AgentWalletContextV2,
  AgentWalletDirectoryResultV1,
  AgentWalletQueryFeatureStatusV1,
} from './protocol/types';
import type { AgentV2SessionStorage } from './sessionStorage';
import type {
  AgentV2HostAccount,
  AgentV2HostAsset,
  AgentV2HostContextSnapshot,
} from './types';

import { APP_NAME } from '../../config';
import contractManifest from './generated/manifest.json';
import { getAgentV2ActionAvailability } from './actionAvailability';
import sessionStorageAdapter from './sessionStorage';
import { createWalletAuthoritySnapshot } from './walletAuthority';
import { AgentV2WalletRefRegistry } from './walletRefRegistry';

const MAX_HOST_ACCOUNTS = 100;
const MAX_HOST_ASSETS = 10_000;

const WALLET_SESSION_STORAGE_KEY = 'agentV2WalletSession';
const WALLET_SESSION_STORAGE_VERSION = 2;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const ACCOUNT_TYPES = new Set<AgentV2HostAccount['accountType']>([
  'regular',
  'ledger',
  'viewOnly',
  'multisig',
  'unknown',
]);

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
  private authoritySnapshot = createWalletAuthoritySnapshot();
  private walletQueryStatus: AgentWalletQueryFeatureStatusV1 = 'disabled';
  private walletFilterCatalogDigest?: string;
  private readonly refs = new AgentV2WalletRefRegistry();
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
    const nextSnapshot = normalizeHostContext(snapshot);
    const authoritySnapshot = createWalletAuthoritySnapshot(nextSnapshot, this.authoritySnapshot);
    const nextAuthorityFingerprint = authoritySnapshot.authorityFingerprint;
    const nextQueryAuthorityFingerprint = authoritySnapshot.queryFingerprint;
    const hasAuthorityChanged = nextAuthorityFingerprint !== this.authorityFingerprint;
    const hasQueryAuthorityChanged = this.queryAuthorityFingerprint !== undefined
      && nextQueryAuthorityFingerprint !== this.queryAuthorityFingerprint;
    const hasWalletContextChanged = hasAuthorityChanged || hasQueryAuthorityChanged;
    if (hasWalletContextChanged) this.revision += 1;
    this.authorityFingerprint = nextAuthorityFingerprint;
    this.queryAuthorityFingerprint = nextQueryAuthorityFingerprint;
    this.host = nextSnapshot;
    this.authoritySnapshot = authoritySnapshot;
    this.refs.reconcile(nextSnapshot);
    this.persist();
    return { hasAuthorityChanged, hasWalletContextChanged };
  }

  updateFeatureCapabilities(capabilities?: AgentFeatureCapabilitiesResponseV2) {
    this.walletQueryStatus = capabilities?.walletQuery.status ?? 'disabled';
    this.walletFilterCatalogDigest = capabilities?.walletQuery.filterCatalog?.digest;
  }

  /** Wallet reads run only when the server offers them with the filter catalog this client was built with */
  isWalletQueryAvailable() {
    return this.walletQueryStatus === 'available'
      && this.walletFilterCatalogDigest === contractManifest.walletFilterCatalogSha256;
  }

  async reset({ shouldClearPersistentState = false }: { shouldClearPersistentState?: boolean } = {}) {
    this.sessionId = this.randomUuid();
    this.revision = 0;
    this.host = undefined;
    this.authorityFingerprint = 'none';
    this.queryAuthorityFingerprint = undefined;
    this.authoritySnapshot = createWalletAuthoritySnapshot();
    this.walletQueryStatus = 'disabled';
    this.walletFilterCatalogDigest = undefined;
    this.refs.clear();
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
      accountRefs: this.refs.accountRefs,
      accountIds: this.refs.accountIds,
      addressRefs: this.refs.addressRefs,
      addresses: this.refs.addresses,
    };
  }

  buildContext(): {
    context: AgentContext;
    capabilities: AgentCapabilities;
    walletContext: AgentWalletContextV2;
  } {
    const host = this.host;
    const activeAccount = host ? findActiveAccount(host) : undefined;
    const ui = host?.uiCapabilities;
    const {
      isNavigationSupported, walletSupportedActions, supportedActions,
    } = getAgentV2ActionAvailability(host);
    const isActiveAccountAvailable = activeAccount?.state === 'active';
    const isWalletQueryAvailable = this.isWalletQueryAvailable();
    const features: AgentClientFeature[] = [
      ...(ui?.supportsFollowups ? ['followups' as const] : []),
      ...(isActiveAccountAvailable && ui?.supportsWalletDirectory && canBuildWalletDirectory(host!)
        ? ['walletDirectory' as const] : []),
      ...(ui?.supportsSendRecipientWithoutAsset && supportedActions.includes('send')
        ? ['sendRecipientWithoutAsset' as const] : []),
      // The server reads the account's public addresses to look them up on the blockchain
      ...(isWalletQueryAvailable ? ['walletChainLookup' as const] : []),
    ];

    const context: AgentContext = {
      platform: host?.platform ?? 'classic',
      client: host?.client ?? 'web',
      lang: host?.lang ?? 'en',
      baseCurrency: host?.baseCurrency ?? 'USD',
      ...(APP_NAME === 'My Wallet' || APP_NAME === 'Gram Wallet' ? { appName: APP_NAME } : {}),
      ...(isWalletQueryAvailable && host?.timeZone && isValidTimeZone(host.timeZone)
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
      protocolVersion: 3,
      supportedActions,
      features,
      ...(isNavigationSupported && isActiveAccountAvailable && host?.builtinDapps?.length
        ? { builtinDapps: host.builtinDapps } : {}),
    };
    const walletContext: AgentWalletContextV2 = !activeAccount || !host?.activeNetwork
      ? { mode: 'none', reason: 'noWallet' }
      : {
        mode: 'wallet',
        sessionId: this.sessionId,
        revision: this.revision,
        activeAccount: {
          accountRef: this.refs.getAccountRef(activeAccount.accountId),
          state: activeAccount.state,
          isViewOnly: activeAccount.isViewOnly,
          chains: activeAccount.chains,
          supportedActions: walletSupportedActions,

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
      accountRef: this.refs.getAccountRef(account.accountId),
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

  async walletAuthorityBinding() {
    while (true) {
      const authority = this.authoritySnapshot;
      const revision = this.revision;
      const sessionId = this.sessionId;
      const binding = await authority.bind(sessionId, revision);
      if (authority === this.authoritySnapshot && sessionId === this.sessionId && revision === this.revision) {
        return binding;
      }
    }
  }

  getAssetRef(accountId: string, slug: string, chain: string) {
    return this.refs.getAssetRef(accountId, slug, chain);
  }

  resolveAssetRef(assetRef: string) {
    return this.refs.resolveAssetRef(assetRef);
  }

  resolveSavedAddressRefs(accountId: string, contactId: string) {
    return this.refs.resolveSavedAddressRefs(accountId, contactId);
  }

  resolveProfileSavedAddressRefs(contactId: string) {
    return this.refs.resolveProfileSavedAddressRefs(contactId);
  }

  resolveWalletAddressRefs(accountId: string, chain: string) {
    return this.refs.resolveWalletAddressRefs(accountId, chain);
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

function normalizeHostContext(snapshot?: AgentV2HostContextSnapshot) {
  if (!snapshot) return;
  if (
    !snapshot.uiCapabilities
    || !Array.isArray(snapshot.uiCapabilities.supportedActions)
    || [
      snapshot.uiCapabilities.supportsFollowups,
      snapshot.uiCapabilities.supportsRunActivity,
      snapshot.uiCapabilities.supportsWalletDirectory,
      snapshot.uiCapabilities.supportsMessageEdit,
      snapshot.uiCapabilities.supportsRegenerate,
    ].some((value) => typeof value !== 'boolean')
    || !Array.isArray(snapshot.accounts)
    || snapshot.accounts.length > MAX_HOST_ACCOUNTS
    || (snapshot.assetCatalog !== undefined && (
      !Array.isArray(snapshot.assetCatalog)
      || snapshot.assetCatalog.length > MAX_HOST_ASSETS
    ))
    || (snapshot.swapAssetCatalog !== undefined && (
      !Array.isArray(snapshot.swapAssetCatalog)
      || snapshot.swapAssetCatalog.length > MAX_HOST_ASSETS
    ))
    || (snapshot.isLandscape !== undefined && typeof snapshot.isLandscape !== 'boolean')
    || (snapshot.isTestnet !== undefined && typeof snapshot.isTestnet !== 'boolean')
    || !Array.isArray(snapshot.savedAddresses)
    || (snapshot.isStakingDisabled !== undefined && typeof snapshot.isStakingDisabled !== 'boolean')
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
      || (account.nftLoadedChains !== undefined && !Array.isArray(account.nftLoadedChains))
    ) {
      throw new Error('Invalid Agent V2 account context');
    }
  }
  const assetCatalog = snapshot.assetCatalog?.filter(isValidHostAsset);
  const swapAssetCatalog = snapshot.swapAssetCatalog?.filter(isValidSwapAsset);
  if (
    assetCatalog?.length === snapshot.assetCatalog?.length
    && swapAssetCatalog?.length === snapshot.swapAssetCatalog?.length
  ) return snapshot;

  return {
    ...snapshot,
    assetCatalog,
    swapAssetCatalog,
  };
}

function isValidHostAsset(asset: AgentV2HostAsset) {
  return isValidSwapAsset(asset)
    && (asset.percentChange24h === undefined || isValidDecimal(asset.percentChange24h));
}

function isValidSwapAsset(asset: AgentV2HostAsset) {
  return Boolean(asset && typeof asset === 'object')
    && Boolean(asset.slug)
    && Boolean(asset.chain)
    && Boolean(asset.symbol)
    && Number.isInteger(asset.decimals)
    && asset.decimals >= 0
    && (asset.priceUsd === undefined || isValidUnsignedDecimal(asset.priceUsd));
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
