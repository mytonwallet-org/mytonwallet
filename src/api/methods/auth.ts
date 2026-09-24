import type { ApiTonWalletVersion } from '../chains/ton/types';
import type {
  ApiAccountAny,
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiActivityTimestamps,
  ApiAnyDisplayError,
  ApiAuthImportViewAccountResult,
  ApiBalanceBySlug,
  ApiBip39Account,
  ApiChain,
  ApiDerivation,
  ApiGroupedWalletVariant,
  ApiImportAddressByChain,
  ApiLedgerAccount,
  ApiLedgerAccountInfo,
  ApiLedgerWalletInfo,
  ApiNetwork,
  ApiTonWallet,
  ApiViewAccount,
  ApiWalletByChain,
  OnApiUpdate,
} from '../types';
import { ApiCommonError } from '../types';

import { parseAccountId } from '../../util/account';
import { getChainConfig, getChainsByStandard, getOrderedAccountChains, getSupportedChains } from '../../util/chain';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { range } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { createTaskQueue } from '../../util/schedulers';
import { getChainBySlug } from '../../util/tokens';
import chains from '../chains';
// The TON backend auth token is signed from the already-decrypted mnemonic during import; it is a backend
// concern rather than a chain capability, so it stays a direct import until it gets its own SDK group.
import * as ton from '../chains/ton';
import {
  fetchStoredAccount,
  fetchStoredAccounts,
  fetchStoredChainAccount,
  getAccountChains,
  getNewAccountId,
  removeAccountValue,
  removeNetworkAccountsValue,
  setAccountValue,
  updateStoredAccount,
  updateStoredWallet,
} from '../common/accounts';
import {
  generateBip39Mnemonic,
  getMnemonic,
  validateBip39Mnemonic,
} from '../common/mnemonic';
import { sendUpdateTokens } from '../common/tokens';
import { tokenRepository } from '../db';
import { getEnvironment } from '../environment';
import { handleServerError } from '../errors';
import { storage } from '../storages';
import { activateAccount, deactivateAllAccounts } from './accounts';
import { removeAccountDapps, removeAllDapps, removeNetworkDapps } from './dapps';
import { isBackendAuthTokenValid } from './other';
import {
  addPollingAccount,
  removeAllPollingAccounts,
  removeNetworkPollingAccounts,
  removePollingAccount,
} from './polling';

let onUpdate: OnApiUpdate;

/** HD index gap so extra UTXO address-format accounts do not share wallets on other chains. */
const ADDRESS_FORMAT_IMPORT_INDEX_OFFSET = 1000;

type WalletWithChain = ApiWalletByChain[ApiChain] & { chain: ApiChain };

function getWalletForReplacement<
  T extends ApiChain,
  TWallet extends ApiWalletByChain[T] | Omit<ApiWalletByChain[T], 'index'>,
>(chain: T, wallet: TWallet) {
  if (chain !== 'ton') return wallet;

  const { authToken: _authToken, ...walletWithoutAuthToken } = wallet as ApiTonWallet;
  return walletWithoutAuthToken as TWallet;
}

/**
 * Signs the backend auth token using the already decrypted mnemonic, so creating it costs
 * no extra Enclave export. Returns `undefined` when the token does not match the wallet's
 * stored public key (e.g. the mnemonic holds a private key of another chain).
 */
async function buildTonBackendAuthToken(mnemonic: string[], account: ApiAccountWithMnemonic) {
  const tonWallet = account.byChain.ton;
  if (!tonWallet?.publicKey || tonWallet.authToken) return undefined;

  try {
    const keyPair = await ton.getKeyPairFromStoredMnemonic(mnemonic, account);
    const authToken = ton.buildBackendAuthToken(keyPair.secretKey);

    return isBackendAuthTokenValid(authToken, tonWallet.publicKey) ? authToken : undefined;
  } catch (err) {
    logDebugError('buildTonBackendAuthToken', err);

    return undefined;
  }
}

export function initAuth(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

/**
 * TON's 24-word scheme is the only native (non-BIP39) mnemonic the app supports, and the wallets derived
 * from it are stored as TON wallets.
 */
function findNativeMnemonic() {
  return chains.ton?.nativeMnemonic;
}

function resolveNativeMnemonic() {
  const nativeMnemonic = findNativeMnemonic();
  if (!nativeMnemonic) {
    throw new Error('Native mnemonic is not supported in this build');
  }

  return nativeMnemonic;
}

export function generateMnemonic(isBip39: boolean) {
  if (isBip39) return generateBip39Mnemonic();

  return resolveNativeMnemonic().generateMnemonic();
}

export async function validateMnemonic(mnemonic: string[]) {
  // Every build accepts a BIP39 phrase, even one that only ever mints TON-specific ones: a wallet has to stay
  // restorable in the app that created it, whichever way that app was built at the time.
  if (validateBip39Mnemonic(mnemonic)) {
    return true;
  }

  const nativeMnemonic = findNativeMnemonic();
  return nativeMnemonic ? nativeMnemonic.validateMnemonic(mnemonic) : false;
}

export async function importMnemonic(
  networks: ApiNetwork[],
  mnemonic: string[],
  shouldSkipDiscovery?: boolean,
) {
  const isBip39Mnemonic = validateBip39Mnemonic(mnemonic);
  const nativeMnemonic = findNativeMnemonic();
  const isTonMnemonic = nativeMnemonic ? await nativeMnemonic.validateMnemonic(mnemonic) : false;

  if (!isBip39Mnemonic && !isTonMnemonic) {
    throw new Error('Invalid mnemonic');
  }

  try {
    // Phase 1: derive every network's wallets without touching storage. The TON history probe can throw on an
    // unreachable node, so deriving up front means such a failure aborts before anything is persisted; a partial
    // write would otherwise leave a ghost account that a retry duplicates.
    const derivedByNetwork = await Promise.all(networks.map(async (network) => {
      let accounts: (ApiAccountWithMnemonic & { derivedFromIndex?: number })[] = [];
      let tonWallet: ApiTonWallet & { lastTxId?: string } | undefined;
      let shouldForceTonMnemonic = false;

      if (!shouldSkipDiscovery && isBip39Mnemonic && isTonMnemonic) {
        // On-chain history is the only tiebreaker between the two derivations, and they yield different addresses.
        // An unreachable node must therefore abort the import (the caller turns it into a retriable error) rather
        // than read as "no history" and quietly hand the user a BIP39 address instead of their funded one.
        tonWallet = await nativeMnemonic!.getWalletFromMnemonic(network, mnemonic, false);
        if (tonWallet.lastTxId) {
          shouldForceTonMnemonic = true;
        }
      }

      if (isBip39Mnemonic && !shouldForceTonMnemonic) {
        accounts = await buildBip39Accounts(network, mnemonic, shouldSkipDiscovery);
      } else {
        tonWallet ||= await nativeMnemonic!.getWalletFromMnemonic(network, mnemonic);
        accounts = [{
          type: 'ton',
          byChain: {
            ton: tonWallet,
          },
        }];
      }

      // We need to preserve accountId in account object for return
      const sortedAccounts: (ApiAccountWithMnemonic & { id?: string; derivedFromIndex?: number })[]
      = accounts.sort((a, b) => (a.derivedFromIndex ?? 0) - (b.derivedFromIndex ?? 0));

      return { network, sortedAccounts };
    }));

    // Phase 2: every network derived successfully, so the storage writes below cannot be interrupted part way
    // through by a probe failure on another network.
    const imported: { accountId: string; byChain: ReturnType<typeof getAccountChains> }[] = [];
    let firstPrimaryAccountId: string | undefined;

    for (const { network, sortedAccounts } of derivedByNetwork) {
      for (const account of sortedAccounts) {
        // Persist a copy stripped of the transient id and derivedFromIndex fields, and never touch it again, so a
        // storage backend that caches the value by reference cannot pick up a stray id from a later mutation.
        const accountToSave = { ...account };
        delete accountToSave.id;
        delete accountToSave.derivedFromIndex;

        const authToken = await buildTonBackendAuthToken(mnemonic, accountToSave);
        if (authToken) {
          accountToSave.byChain = {
            ...accountToSave.byChain,
            ton: { ...accountToSave.byChain.ton!, authToken },
          };
        }

        const accountId = await addAccount(network, accountToSave);
        firstPrimaryAccountId ??= accountId;

        imported.push({ accountId, byChain: getAccountChains(accountToSave) });
      }
    }

    if (!firstPrimaryAccountId) {
      throw new Error('No primary account found');
    }

    void activateAccount(firstPrimaryAccountId);

    return imported;
  } catch (err) {
    return handleServerError(err);
  }
}

async function buildBip39Accounts(
  network: ApiNetwork,
  mnemonic: string[],
  shouldSkipDiscovery?: boolean,
): Promise<(ApiAccountWithMnemonic & { derivedFromIndex?: number })[]> {
  if (shouldSkipDiscovery) {
    return [{
      derivedFromIndex: 0,
      type: 'bip39',
      byChain: await getNewMnemonicWallets(network, mnemonic),
    }];
  }

  const walletGroupsByIndex = await findBip39WalletGroups(network, mnemonic);

  return walletGroupsByIndex.map(({ index, wallets }) => ({
    derivedFromIndex: index,
    type: 'bip39' as const,
    byChain: Object.fromEntries(wallets.map((e) => [e.chain, e])),
  }));
}

async function deriveChainWallets(
  network: ApiNetwork,
  mnemonic: string[],
  chain: ApiChain,
  derivation?: ApiDerivation,
): Promise<WalletWithChain[]> {
  // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
  // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
  // some type checking.
  const typedChain = chain as 'ton';
  const wallets = await chains[typedChain].getWalletFromBip39Mnemonic(network, mnemonic, derivation);

  return wallets.map((wallet) => ({ ...wallet, chain } as WalletWithChain));
}

async function deriveChainWallet(
  network: ApiNetwork,
  mnemonic: string[],
  chain: ApiChain,
  derivation?: ApiDerivation,
): Promise<WalletWithChain | undefined> {
  const [wallet] = await deriveChainWallets(network, mnemonic, chain, derivation);

  return wallet;
}

function buildDerivationAtIndex(chain: ApiChain, index: number, template?: ApiDerivation): ApiDerivation {
  const defaultDerivation = chains[chain as 'ton'].getDefaultDerivation();

  return {
    path: template?.path ?? defaultDerivation.path,
    index,
    label: template?.label ?? defaultDerivation.label,
  };
}

async function findBip39WalletGroups(network: ApiNetwork, mnemonic: string[]) {
  const chainKeys = Object.keys(chains) as (keyof typeof chains)[];
  const walletGroups = await Promise.all(chainKeys.map((chain) => (
    deriveChainWallets(network, mnemonic, chain)
  )));

  const walletsByDerivationIndex = new Map<number, WalletWithChain[]>();

  for (const e of walletGroups.flat()) {
    const idx = e.derivation?.index ?? 0;
    if (!walletsByDerivationIndex.has(idx)) {
      walletsByDerivationIndex.set(idx, []);
    }
    walletsByDerivationIndex.get(idx)!.push(e);
  }

  // For non-zero derivation indices, fill in chains that were missing (had no balance there)
  // using the derivation path from the chain's index-0 wallet.
  const allChainKeys = Object.keys(chains) as ApiChain[];
  const index0Group = walletsByDerivationIndex.get(0) ?? [];

  for (const [derivationIndex, groupWallets] of walletsByDerivationIndex) {
    if (derivationIndex === 0) continue;

    const foundChains = new Set(groupWallets.map((w) => w.chain));

    await Promise.all(allChainKeys.map(async (chain) => {
      if (foundChains.has(chain)) return;

      const chain0Wallet = index0Group.find((w) => w.chain === chain);
      const fillerWallet = chain0Wallet?.derivation?.path
        ? await deriveChainWallet(
          network,
          mnemonic,
          chain,
          buildDerivationAtIndex(chain, derivationIndex, chain0Wallet.derivation),
        )
        : await deriveChainWallet(network, mnemonic, chain);

      if (fillerWallet) {
        groupWallets.push(fillerWallet);
      }
    }));
  }

  const grouped = await Promise.all(
    [...walletsByDerivationIndex.entries()].map(async ([index, wallets]) => {
      const splitGroups = await splitWalletGroupByDistinctAddresses(network, mnemonic, wallets);

      return splitGroups.map((group) => ({ index, wallets: group }));
    }),
  );

  return grouped.flat();
}

async function splitWalletGroupByDistinctAddresses(
  network: ApiNetwork,
  mnemonic: string[],
  wallets: WalletWithChain[],
): Promise<WalletWithChain[][]> {
  const byChain = new Map<ApiChain, WalletWithChain[]>();

  for (const wallet of wallets) {
    const list = byChain.get(wallet.chain) ?? [];
    if (!list.some((item) => item.address === wallet.address)) {
      list.push(wallet);
    }
    byChain.set(wallet.chain, list);
  }

  const primary = [...byChain.values()].map((list) => {
    if (!getChainConfig(list[0].chain).doesImportAddressFormatsSeparately) {
      return list[list.length - 1];
    }

    const defaultPath = getChainConfig(list[0].chain).defaultDerivationPath;
    return list.find((wallet) => wallet.derivation?.path === defaultPath) ?? list[0];
  });

  const extras = [...byChain.values()].flatMap((list) => {
    if (!getChainConfig(list[0].chain).doesImportAddressFormatsSeparately) {
      return [];
    }

    const primaryWallet = primary.find((wallet) => wallet.chain === list[0].chain)!;
    return list.filter((wallet) => wallet.address !== primaryWallet.address);
  });

  if (!extras.length) {
    return [primary];
  }

  const extraGroups = await Promise.all(extras.map(async (extra, extraIndex) => {
    const offsetIndex = (extra.derivation?.index ?? 0)
      + ADDRESS_FORMAT_IMPORT_INDEX_OFFSET * (extraIndex + 1);

    return Promise.all(primary.map(async (wallet) => {
      if (wallet.chain === extra.chain) {
        return extra;
      }

      const derivedWallet = await deriveChainWallet(
        network,
        mnemonic,
        wallet.chain,
        buildDerivationAtIndex(wallet.chain, offsetIndex, wallet.derivation),
      );

      return derivedWallet ?? wallet;
    }));
  }));

  return [primary, ...extraGroups];
}

async function getNewMnemonicWallets(network: ApiNetwork, mnemonic: string[]) {
  const byChain: ApiBip39Account['byChain'] = {};

  await Promise.all((Object.keys(chains) as ApiChain[]).map(async (_chain) => {
    // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
    // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
    // some type checking.
    const chain = _chain as 'ton';
    const derivation = chains[chain].getDefaultDerivation();

    const [wallet] = await chains[chain].getWalletFromBip39Mnemonic(
      network, mnemonic, derivation, true,
    );

    if (wallet) {
      (byChain as Record<ApiChain, ApiWalletByChain[ApiChain]>)[chain] = wallet;
    }
  }));

  return byChain;
}

export async function importPrivateKey(
  chain: ApiChain,
  networks: ApiNetwork[],
  privateKey: string,
) {
  return Promise.all(networks.map(async (network) => {
    const wallet = await chains[chain].getWalletFromPrivateKey(network, privateKey);
    const account: ApiBip39Account = {
      type: 'bip39',
      byChain: { [chain]: wallet },
    };
    const accountId = await addAccount(network, account);
    void activateAccount(accountId);

    return {
      accountId,
      byChain: getAccountChains(account),
    };
  }));
}

export async function importLedgerAccount(network: ApiNetwork, accountInfo: ApiLedgerAccountInfo) {
  const { byChain, driver, deviceId, deviceName } = accountInfo;

  const account: ApiLedgerAccount = {
    type: 'ledger',
    byChain,
    driver,
    deviceId,
    deviceName,
  };

  const accountId = await addAccount(network, account);

  return { accountId, byChain: getAccountChains(account) };
}

export async function getLedgerWallets(
  chain: ApiChain,
  network: ApiNetwork,
  startWalletIndex: number,
  count: number,
): Promise<ApiLedgerWalletInfo[] | { error: ApiAnyDisplayError }> {
  if (process.env.NO_LEDGER === '1') throw new Error('Ledger is disabled');

  const { getLedgerDeviceInfo } = await import('../common/ledger');
  const { driver, deviceId, deviceName } = await getLedgerDeviceInfo();

  const walletInfos = await chains[chain].getWalletsFromLedgerAndLoadBalance(
    network,
    range(startWalletIndex, startWalletIndex + count),
  );
  if ('error' in walletInfos) return walletInfos;

  return walletInfos.map((walletInfo) => ({
    ...walletInfo,
    driver,
    deviceId,
    deviceName,
  }));
}

// When multiple Ledger accounts are imported, they all are created simultaneously. This causes a race condition causing
// multiple accounts having the same id. `createTaskQueue(1)` forces the accounts to be imported sequentially.
const addAccountMutex = createTaskQueue(1);

async function addAccount(network: ApiNetwork, account: ApiAccountAny, preferredId?: number) {
  const accountId = await addAccountMutex.run(async () => {
    const accountId = await getNewAccountId(network, preferredId);
    await setAccountValue(accountId, 'accounts', account);
    return accountId;
  });

  addPollingAccount(accountId, account);

  return accountId;
}

export async function removeNetworkAccounts(network: ApiNetwork) {
  removeNetworkPollingAccounts(network);

  await Promise.all([
    deactivateAllAccounts(),
    removeNetworkAccountsValue(network, 'accounts'),
    getEnvironment().isDappSupported && removeNetworkDapps(network),
  ]);
}

export async function resetAccounts() {
  removeAllPollingAccounts();

  let agentV2Reset: Promise<void> | undefined;
  if (process.env.NO_EXTRA_FEATURES !== '1') {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { resetAgentV2 } = require('./agentV2Lifecycle') as typeof import('./agentV2Lifecycle');
    agentV2Reset = resetAgentV2();
  }

  await Promise.all([
    deactivateAllAccounts(),
    storage.removeItem('accounts'),
    getEnvironment().isDappSupported && removeAllDapps(),
    tokenRepository.clear(),
    agentV2Reset,
  ]);
}

export async function removeAccount(
  accountId: string,
  nextAccountId: string | undefined,
  newestActivityTimestamps?: ApiActivityTimestamps,
) {
  removePollingAccount(accountId);

  await Promise.all([
    removeAccountValue(accountId, 'accounts'),
    getEnvironment().isDappSupported && removeAccountDapps(accountId),
  ]);

  if (nextAccountId !== undefined) {
    await activateAccount(nextAccountId, newestActivityTimestamps);
  }
}

function findMultichainUpgradeCandidates(accounts: Record<string, ApiAccountAny>, accountIds?: string[]) {
  const supportedChains = getSupportedChains();
  const allowedAccountIds = accountIds ? new Set(accountIds) : undefined;

  return Object.entries(accounts).filter(([accountId, account]) => {
    if (allowedAccountIds && !allowedAccountIds.has(accountId)) return false;
    if (account.type !== 'bip39' && account.type !== 'ton') return false;

    const hasMissingChains = account.type === 'bip39'
      && supportedChains.some(
        (chain) => !account.byChain?.[chain]?.derivation && getChainConfig(chain).isSubwalletsSupported,
      );

    const tonWallet = account.byChain?.ton;
    const hasMissingAuthToken = Boolean(tonWallet?.publicKey && !tonWallet.authToken);

    return hasMissingChains || hasMissingAuthToken;
  }) as [string, ApiAccountWithMnemonic][];
}

export async function getMultichainUpgradeCandidateIds(accountIds?: string[]) {
  const accounts = await fetchStoredAccounts();

  return findMultichainUpgradeCandidates(accounts, accountIds).map(([accountId]) => accountId);
}

export async function upgradeMultichainAccounts(enclaveToken: string, accountIds?: string[]) {
  const supportedChains = getSupportedChains();

  const accounts = await fetchStoredAccounts();

  const accountsToUpgrade = findMultichainUpgradeCandidates(accounts, accountIds);

  if (accountsToUpgrade.length) {
    logDebug('Upgrade multichain accounts', accountsToUpgrade.map((e) => e[0]));
  }

  for (const [accountId, account] of accountsToUpgrade) {
    const mnemonic = await getMnemonic(accountId, enclaveToken);

    if (!mnemonic) {
      return { error: ApiCommonError.InvalidPassword };
    }

    // The mnemonic is already decrypted here, so creating the missing auth token costs no extra Enclave export
    const backfilledAuthToken = await buildTonBackendAuthToken(mnemonic, account);
    if (backfilledAuthToken) {
      await updateStoredWallet(accountId, 'ton', { authToken: backfilledAuthToken });
    }

    if (isMnemonicPrivateKey(mnemonic) || account.type !== 'bip39') {
      continue;
    }

    const { network } = parseAccountId(accountId);

    const chainsToAdd = supportedChains.filter(
      (chain) => getChainConfig(chain).isSubwalletsSupported && !account.byChain?.[chain]?.derivation,
    );

    const derived = await Promise.all(chainsToAdd.map(async (chain) => {
      try {
        const [wallet] = await (chains[chain].getWalletFromBip39Mnemonic as any)(network, mnemonic, undefined, true);
        return wallet ? { chain, wallet } : undefined;
      } catch (err) {
        logDebugError('upgradeMultichainAccounts: chain failed', { accountId, chain }, err);
        return undefined;
      }
    }));

    const addedWallets = derived.filter(Boolean);
    if (!addedWallets.length) {
      continue;
    }

    // Re-read before writing so changes made meanwhile (e.g. in another tab) are not lost
    const fresh = await fetchStoredAccount<ApiBip39Account>(accountId);
    const mergedByChain = { ...(fresh.byChain ?? {}) };
    const persistedWallets = addedWallets.filter(({ chain }) => !mergedByChain[chain]?.derivation);
    for (const { chain, wallet } of persistedWallets) {
      (mergedByChain as Record<ApiChain, ApiWalletByChain[ApiChain]>)[chain] = wallet;
    }

    await updateStoredAccount<ApiBip39Account>(accountId, { byChain: mergedByChain });

    for (const { chain, wallet } of persistedWallets) {
      onUpdate({
        type: 'updateAccount',
        accountId,
        chain,
        address: wallet.address,
        derivation: wallet.derivation,
      });
    }
  }
}

export async function repairInvalidBip39TonAuthTokens() {
  const accounts = await fetchStoredAccounts();

  for (const [accountId, account] of Object.entries(accounts)) {
    if (account.type !== 'bip39') continue;

    const tonWallet = account.byChain.ton;
    if (!tonWallet?.authToken || !tonWallet.publicKey) continue;

    // Older subwallet creation could retain a parent signature after TON identity changed, which backend auth rejects.
    // Clear that cache so normal password-backed signing regenerates it for the current wallet.
    if (!isBackendAuthTokenValid(tonWallet.authToken, tonWallet.publicKey)) {
      await updateStoredWallet(accountId, 'ton', { authToken: undefined });
    }
  }
}

export async function importViewAccount(
  network: ApiNetwork,
  addressByChain: ApiImportAddressByChain,
  isTemporary?: true,
): Promise<{ error: ApiAnyDisplayError } | { error: string; chain: ApiChain } | ApiAuthImportViewAccountResult> {
  try {
    const account: ApiViewAccount = {
      type: 'view',
      byChain: {},
    };
    let title: string | undefined;
    const errors: { error: string; chain: ApiChain }[] = [];

    await Promise.all(Object.entries(addressByChain).map(async ([_chain, address]) => {
      // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
      // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
      // some type checking.
      const chain = _chain as 'ton';
      const wallet = await chains[chain].getWalletFromAddress(network, address);
      if ('error' in wallet) {
        errors.push({ ...wallet, chain });
        return;
      }

      account.byChain[chain] = wallet.wallet;
      if (wallet.title) title = wallet.title;
    }));

    // Import of all submitted addresses failed
    if (errors.length && errors.length === Object.keys(addressByChain).length) return errors[0];

    if (errors.length) {
      // An error occurred while importing some of the addresses.
      // We are transferring it to the logs.
      for (const error of errors) {
        logDebugError('Import view address: ', error);
      }
    }

    const accountId = await addAccount(network, account);
    void activateAccount(accountId);

    return {
      accountId,
      title,
      byChain: getAccountChains(account),
      ...(isTemporary && { isTemporary: true }),
    };
  } catch (err) {
    return handleServerError(err);
  }
}

export async function importNewWalletVersion(
  accountId: string,
  version: ApiTonWalletVersion,
  isTestnetSubwalletId?: boolean,
): Promise<{
  isNew: true;
  accountId: string;
  byChain: ReturnType<typeof getAccountChains>;
} | {
  isNew: false;
  accountId: string;
}> {
  const { network } = parseAccountId(accountId);
  const account = await fetchStoredChainAccount(accountId, 'ton');
  // Wallet versions are a TON concept, and the derived wallet is stored back as the account's TON wallet
  const getOtherVersionWallet = chains.ton?.getOtherVersionWallet;
  if (!getOtherVersionWallet) {
    throw new Error('Wallet versions are not supported in this build');
  }

  const newAccount: ApiAccountWithChain<'ton'> = {
    ...account,
    byChain: {
      ton: getOtherVersionWallet(network, account.byChain.ton, version, isTestnetSubwalletId),
    },
  };

  const accounts = await fetchStoredAccounts();
  const existingAccount = Object.entries(accounts).find(([, account]) => {
    return account.byChain.ton?.address === newAccount.byChain.ton.address && account.type === newAccount.type;
  });

  if (existingAccount) {
    return {
      isNew: false,
      accountId: existingAccount[0],
    };
  }

  const newAccountId = await addAccount(network, newAccount);

  return {
    isNew: true,
    accountId: newAccountId,
    byChain: getAccountChains(newAccount),
  };
}

const SETTINGS_SUBWALLET_PAGE_SIZE = 4;

function isGroupedVariantSameAsCurrentAccount(
  account: ApiBip39Account,
  byChain: ApiGroupedWalletVariant['byChain'],
) {
  for (const chain of Object.keys(byChain) as ApiChain[]) {
    const entry = byChain[chain];
    if (!entry) return false;
    if (account.byChain[chain]?.address !== entry.wallet.address) {
      return false;
    }
  }
  return true;
}

async function maybeMigrateSolanaDerivation(
  accountId: string,
  account: ApiBip39Account,
  pageGroups: ApiGroupedWalletVariant[],
) {
  const solanaAccount = account.byChain.solana;
  if (!solanaAccount?.address || solanaAccount.derivation) return;

  for (const group of pageGroups) {
    const sol = group.byChain.solana;
    if (!sol?.hasDerivation || sol.wallet.address !== solanaAccount.address) continue;
    const { path, index, label } = sol.wallet.derivation ?? {};
    if (path === undefined || typeof index !== 'number') continue;

    await updateStoredWallet(accountId, 'solana', {
      derivation: { path, index, ...(label !== undefined && { label }) },
    });

    break;
  }
}

export async function getWalletVariants(
  accountId: string,
  page: number,
  mnemonic: string[],
): Promise<ApiGroupedWalletVariant[] | { error: ApiAnyDisplayError }> {
  if (!mnemonic?.length) {
    return { error: ApiCommonError.Unexpected };
  }

  const account = await fetchStoredAccount<ApiBip39Account>(accountId);

  if (account.type !== 'bip39') {
    return { error: ApiCommonError.Unexpected };
  }

  const { network } = parseAccountId(accountId);

  const offset = page * SETTINGS_SUBWALLET_PAGE_SIZE;
  const pageGroups: ApiGroupedWalletVariant[] = [];

  const knownChains = getSupportedChains();

  await Promise.all(Array.from({ length: SETTINGS_SUBWALLET_PAGE_SIZE }, async (_, i) => {
    const index = offset + i;
    const byChain: ApiGroupedWalletVariant['byChain'] = {};
    let anyPositive = false;

    await Promise.all(knownChains.map(async (chain) => {
      const parentWallet = account.byChain[chain];

      if (!parentWallet) return;

      const config = getChainConfig(chain);

      if (config.chainStandard && config.chainStandard !== chain) {
        return;
      }

      let pathTemplate = parentWallet.derivation?.path;

      if (!pathTemplate) {
        pathTemplate = getChainConfig(chain).defaultDerivationPath;
      }

      if (!pathTemplate) {
        return { error: ApiCommonError.Unexpected };
      }

      const derivation: ApiDerivation = {
        path: pathTemplate,
        index,
        label: parentWallet.derivation?.label,
      };

      const wallets = await chains[chain].getWalletFromBip39Mnemonic(network, mnemonic, derivation);
      const wallet = wallets[0];

      if (!wallet) {
        return { error: ApiCommonError.Unexpected };
      }

      const { index: _walletIndex, ...walletRest } = wallet;

      if (config.chainStandard) {
        const crosschainAssets = await chains[chain]
          .crosschain!.fetchCrosschainAccountAssets(network, walletRest.address, () => {});

        if (Object.values(crosschainAssets).some((balance) => balance > 0n)) {
          anyPositive = true;
        }

        const crosschainAssetsByChain = new Map<ApiChain, ApiBalanceBySlug>();

        for (const [slug, balance] of Object.entries(crosschainAssets)) {
          const assetChain = getChainBySlug(slug);

          if (!knownChains.includes(assetChain)) {
            continue;
          }

          crosschainAssetsByChain.set(assetChain, {
            ...crosschainAssetsByChain.get(assetChain),
            [slug]: balance,
          });
        }

        const chainsByStandard = getChainsByStandard(config.chainStandard);

        for (const chainOfStandard of chainsByStandard) {
          byChain[chainOfStandard] = {
            wallet: walletRest as Omit<ApiWalletByChain[typeof chainOfStandard], 'index'>,
            balancesBySlug: crosschainAssetsByChain.get(chainOfStandard) ?? {},
            hasDerivation: true,
          };
        }
      } else {
        const balancesBySlug = await chains[chain].getWalletAssets(network, walletRest.address, () => {});

        if (Object.values(balancesBySlug).some((balance) => balance > 0n)) anyPositive = true;

        byChain[chain] = {
          wallet: walletRest as Omit<ApiWalletByChain[typeof chain], 'index'>,
          balancesBySlug,
          hasDerivation: true,
        };
      }
    }));

    if (!anyPositive || isGroupedVariantSameAsCurrentAccount(account, byChain)) {
      return;
    }

    pageGroups.push({
      index,
      byChain,
    });
  }));

  pageGroups.sort((a, b) => a.index - b.index);

  if (onUpdate) {
    sendUpdateTokens(onUpdate);
  }

  if (page === 0) {
    await maybeMigrateSolanaDerivation(accountId, account, pageGroups);
  }

  return pageGroups;
}

function getNextSubWalletIndex(
  account: ApiBip39Account,
  siblings: ApiAccountAny[],
  chainKeys: ApiChain[],
) {
  const parentIndices = chainKeys
    .map((chain) => account.byChain[chain]?.derivation?.index)
    .filter((index): index is number => typeof index === 'number');

  let nextIndex = (parentIndices.length ? Math.max(...parentIndices) : -1) + 1;

  while (siblings.some((sibling) => {
    if (sibling.type !== 'bip39') return false;

    return chainKeys.some((chain) => {
      const parentPath = account.byChain[chain]?.derivation?.path;
      const siblingDerivation = sibling.byChain[chain]?.derivation;

      return Boolean(
        parentPath
        && siblingDerivation?.path === parentPath
        && siblingDerivation.index === nextIndex,
      );
    });
  })) {
    nextIndex += 1;
  }

  return nextIndex;
}

export async function createSubWallet(accountId: string, enclaveToken: string) {
  try {
    const account = await fetchStoredAccount<ApiBip39Account>(accountId);

    if (account.type !== 'bip39') {
      return { error: ApiCommonError.Unexpected };
    }

    const mnemonic = await getMnemonic(accountId, enclaveToken);

    if (!mnemonic) {
      return { error: ApiCommonError.InvalidPassword };
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return { error: ApiCommonError.Unexpected };
    }

    const { network } = parseAccountId(accountId);
    const stored = await fetchStoredAccounts();

    const siblings = Object.entries(stored).filter(([id, acc]) => {
      if (acc.type !== 'bip39') return false;

      return parseAccountId(id).network === network;
    }).map(([, acc]) => acc);

    const chainKeys = getOrderedAccountChains(account.byChain);
    const hasParentDerivation = chainKeys.some((c) => account.byChain[c]?.derivation);

    if (!hasParentDerivation) {
      return { error: ApiCommonError.Unexpected };
    }

    const newIndex = getNextSubWalletIndex(account, siblings, chainKeys);
    const newByChain: ApiBip39Account['byChain'] = {};

    for (const chain of chainKeys) {
      const parentWallet = account.byChain[chain]!;

      let pathTemplate = parentWallet.derivation?.path;
      if (!pathTemplate) {
        pathTemplate = getChainConfig(chain).defaultDerivationPath;
      }

      const derivation: ApiDerivation | undefined = pathTemplate
        ? {
          path: pathTemplate,
          index: newIndex,
          label: parentWallet.derivation?.label,
        }
        : undefined;

      const wallets = await chains[chain].getWalletFromBip39Mnemonic(network, mnemonic, derivation);
      const wallet = wallets[0];

      if (!wallet) {
        return { error: ApiCommonError.Unexpected };
      }

      (newByChain as Record<ApiChain, ApiWalletByChain[ApiChain]>)[chain] = {
        ...getWalletForReplacement(chain, parentWallet),
        ...getWalletForReplacement(chain, wallet),
        index: parentWallet.index,
      } as ApiWalletByChain[typeof chain];
    }

    const duplicateEntry = Object.entries(stored).find(([id, acc]) => {
      if (id === accountId || acc.type === 'view') return false;
      if (parseAccountId(id).network !== network) return false;

      const sameAddresses = chainKeys.every((c) => acc.byChain[c]?.address === newByChain[c]?.address);

      const hasDerivationIndexToMatch = chainKeys.some(
        (c) => typeof newByChain[c]?.derivation?.index === 'number',
      );

      const sameDerivationIndex = hasDerivationIndexToMatch && chainKeys.every((c) => {
        const nextIdx = newByChain[c]?.derivation?.index;

        if (typeof nextIdx !== 'number') return true;

        return acc.byChain[c]?.derivation?.index === nextIdx;
      });

      return sameAddresses || sameDerivationIndex;
    });

    if (duplicateEntry) {
      logDebugError('Duplicate account found (createSubWallet)', duplicateEntry);

      void activateAccount(duplicateEntry[0]);

      return { isNew: false as const, accountId: duplicateEntry[0] };
    }

    const newAccountData: ApiBip39Account = {
      type: 'bip39',
      byChain: newByChain,
    };

    const authToken = await buildTonBackendAuthToken(mnemonic, newAccountData);
    if (authToken) {
      newAccountData.byChain = {
        ...newAccountData.byChain,
        ton: { ...newAccountData.byChain.ton!, authToken },
      };
    }

    const newAccountId = await addAccount(network, newAccountData);

    for (const chain of chainKeys) {
      const w = newByChain[chain]!;

      onUpdate({
        type: 'updateAccount',
        accountId: newAccountId,
        chain,
        address: w.address,
        ...(w.derivation && { derivation: w.derivation }),
      });
    }

    void activateAccount(newAccountId, undefined, true);

    return {
      isNew: true as const,
      accountId: newAccountId,
      byChain: getAccountChains(newAccountData),
    };
  } catch (err) {
    return handleServerError(err);
  }
}

export async function addSubWallet(
  accountId: string,
  partialByChain: Partial<Record<ApiChain, Omit<ApiWalletByChain[ApiChain], 'index'>>>,
  options?: { suppressActivation?: boolean },
) {
  const account = await fetchStoredAccount<ApiBip39Account>(accountId);

  if (account.type !== 'bip39') {
    return { error: ApiCommonError.Unexpected };
  }

  const { network } = parseAccountId(accountId);
  const accounts = await fetchStoredAccounts();
  const chainKeys = Object.keys(partialByChain) as ApiChain[];

  if (!chainKeys.length) {
    return { error: ApiCommonError.Unexpected };
  }

  const duplicate = Object.entries(accounts).find(([id, acc]) => {
    if (id === accountId || acc.type === 'view') return false;
    if (parseAccountId(id).network !== network) return false;

    return chainKeys.every((c) => acc.byChain[c]?.address === partialByChain[c]?.address);
  });

  if (duplicate) {
    logDebugError('Duplicate account found', duplicate);

    if (!options?.suppressActivation) {
      void activateAccount(duplicate[0]);
    }

    return { isNew: false as const, accountId: duplicate[0] };
  }

  const newByChain: ApiBip39Account['byChain'] = { ...account.byChain };

  for (const chain of chainKeys) {
    const parentWallet = account.byChain[chain]!;
    const newWallet = partialByChain[chain]!;

    (newByChain as Record<ApiChain, ApiWalletByChain[ApiChain]>)[chain] = {
      ...getWalletForReplacement(chain, parentWallet),
      ...getWalletForReplacement(chain, newWallet),
      index: parentWallet.index,
      publicKey: newWallet.publicKey || parentWallet.publicKey,
    } as ApiWalletByChain[typeof chain]; // merged chain wallet shapes differ per chain
  }

  const newAccountData: ApiBip39Account = {
    type: 'bip39',
    byChain: newByChain,
  };

  const newAccountId = await addAccount(network, newAccountData);

  for (const chain of chainKeys) {
    const w = newByChain[chain]!;

    onUpdate({
      type: 'updateAccount',
      accountId: newAccountId,
      chain,
      address: w.address,
      ...(w.derivation && { derivation: w.derivation }),
    });
  }

  if (!options?.suppressActivation) {
    void activateAccount(newAccountId, undefined, true);
  }

  return {
    isNew: true as const,
    accountId: newAccountId,
    byChain: getAccountChains(newAccountData),
  };
}

type AddSubWalletOkResult = Extract<Awaited<ReturnType<typeof addSubWallet>>, { accountId: string }>;

function isSubWalletAddError(
  result: Awaited<ReturnType<typeof addSubWallet>>,
): result is { error: ApiCommonError } {
  return Boolean(result && typeof result === 'object' && 'error' in result && !('isNew' in result));
}

export async function addAllFoundSubwallets(
  accountId: string,
  foundWallets: (Partial<Record<ApiChain, Omit<ApiWalletByChain[ApiChain], 'index'>>>)[],
): Promise<{ error: ApiCommonError | ApiAnyDisplayError } | { results: AddSubWalletOkResult[] }> {
  try {
    const walletsToAdd = foundWallets.filter((w) => Object.keys(w).length > 0);

    if (!walletsToAdd.length) {
      return { error: ApiCommonError.Unexpected };
    }

    const results: AddSubWalletOkResult[] = [];

    for (let i = 0; i < walletsToAdd.length; i++) {
      const suppressActivation = i !== walletsToAdd.length - 1;

      const result = await addSubWallet(accountId, walletsToAdd[i], { suppressActivation });

      if (isSubWalletAddError(result)) {
        return result;
      }

      results.push(result);
    }

    return { results };
  } catch (err) {
    return handleServerError(err);
  }
}

/** In explorer mode, we don't need to store all data, only current account, so we clear the storage  */
export async function clearStorageForExplorerMode() {
  const currentAccountId = await storage.getItem('currentAccountId');
  const accounts = await storage.getItem('accounts') as Record<string, ApiAccountAny> | undefined;
  await storage.clear();

  if (currentAccountId && accounts?.[currentAccountId]) {
    await storage.setItem('accounts', { [currentAccountId]: accounts[currentAccountId] });
  }
}
