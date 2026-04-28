import type { ApiTonWalletVersion } from '../chains/ton/types';
import type {
  ApiAccountAny,
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiActivityTimestamps,
  ApiAnyDisplayError,
  ApiAuthImportViewAccountResult,
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

import { IS_TON_MNEMONIC_ONLY } from '../../config';
import { parseAccountId } from '../../util/account';
import { getChainConfig, getOrderedAccountChains, getSupportedChains } from '../../util/chain';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { range } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { createTaskQueue } from '../../util/schedulers';
import chains from '../chains';
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
  decryptMnemonic,
  encryptMnemonic,
  generateBip39Mnemonic,
  getMnemonic,
  validateBip39Mnemonic,
} from '../common/mnemonic';
import { tokenRepository } from '../db';
import { getEnvironment } from '../environment';
import { handleServerError } from '../errors';
import { storage } from '../storages';
import { activateAccount, deactivateAllAccounts } from './accounts';
import { removeAccountDapps, removeAllDapps, removeNetworkDapps } from './dapps';
import {
  addPollingAccount,
  removeAllPollingAccounts,
  removeNetworkPollingAccounts,
  removePollingAccount,
} from './polling';

let onUpdate: OnApiUpdate;

export function initAuth(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export function generateMnemonic(isBip39: boolean) {
  if (isBip39) return generateBip39Mnemonic();
  return ton.generateMnemonic();
}

export async function validateMnemonic(mnemonic: string[]) {
  if (!IS_TON_MNEMONIC_ONLY && validateBip39Mnemonic(mnemonic)) {
    return true;
  }

  return await ton.validateMnemonic(mnemonic);
}

export async function importMnemonic(
  networks: ApiNetwork[],
  mnemonic: string[],
  password: string,
) {
  const isBip39Mnemonic = !IS_TON_MNEMONIC_ONLY && validateBip39Mnemonic(mnemonic);
  const isTonMnemonic = await ton.validateMnemonic(mnemonic);

  if (!isBip39Mnemonic && !isTonMnemonic) {
    throw new Error('Invalid mnemonic');
  }

  const mnemonicEncrypted = await getEncryptedMnemonic(mnemonic, password);
  if (typeof mnemonicEncrypted !== 'string') {
    return mnemonicEncrypted;
  }

  try {
    return (await Promise.all(networks.map(async (network) => {
      let accounts: (ApiAccountWithMnemonic & { derivedFromIndex?: number })[] = [];
      let tonWallet: ApiTonWallet & { lastTxId?: string } | undefined;
      let shouldForceTonMnemonic = false;

      if (isBip39Mnemonic && isTonMnemonic) {
        tonWallet = await ton.getWalletFromMnemonic(network, mnemonic);
        if (tonWallet.lastTxId) {
          shouldForceTonMnemonic = true;
        }
      }

      if (isBip39Mnemonic && !shouldForceTonMnemonic) {
        let foundWallets: (ApiWalletByChain[ApiChain] & { chain: ApiChain })[] = [];

        await Promise.all((Object.keys(chains) as (keyof typeof chains)[]).map(async (_chain) => {
          // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
          // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
          // some type checking.
          const chain = _chain as 'ton';
          const wallets = await chains[chain].getWalletFromBip39Mnemonic(network, mnemonic);

          if (wallets.length > 0) {
            foundWallets = [...foundWallets, ...wallets.map((e) => ({ ...e, chain }))];
          }
        }));

        if (foundWallets.length > 0) {
          type WalletWithChain = ApiWalletByChain[ApiChain] & { chain: ApiChain };
          const walletsByDerivationIndex = new Map<number, WalletWithChain[]>();

          for (const e of foundWallets) {
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

            await Promise.all(allChainKeys.map(async (_chain) => {
              // TypeScript emits false notices, because it doesn't see relations between the key and value
              // types in record mapping. We lock the key type to one of the possible values to resolve the
              // TS notices and have at least some type checking.
              const chain = _chain as 'ton';
              if (foundChains.has(chain)) return;

              // Derive the chain's path from its index-0 wallet
              const chain0Wallet = index0Group.find((w) => w.chain === chain);

              if (!chain0Wallet?.derivation?.path) {
                const [placeholderWallet] = await chains[chain].getWalletFromBip39Mnemonic(
                  network, mnemonic,
                );
                if (placeholderWallet) {
                  groupWallets.push({ ...placeholderWallet, chain });
                }
                return;
              }

              const fillerDerivation: ApiDerivation = {
                path: chain0Wallet.derivation.path,
                index: derivationIndex,
                label: chain0Wallet.derivation.label,
              };

              const [fillerWallet] = await chains[chain].getWalletFromBip39Mnemonic(
                network, mnemonic, fillerDerivation,
              );

              if (fillerWallet) {
                groupWallets.push({ ...fillerWallet, chain });
              }
            }));
          }

          for (const [index, wallets] of walletsByDerivationIndex) {
            accounts.push({
              derivedFromIndex: index,
              type: 'bip39',
              mnemonicEncrypted,
              byChain: Object.fromEntries(wallets.map((e) => [e.chain, e])),
            });
          }
        }
      } else {
        tonWallet ||= await ton.getWalletFromMnemonic(network, mnemonic);
        accounts = [{
          type: 'ton',
          mnemonicEncrypted,
          byChain: {
            ton: tonWallet,
          },
        }];
      }

      let primaryAccountId: string | undefined;

      // We need to preserve accountId in account object for return
      const sortedAccounts: (ApiAccountWithMnemonic & { id?: string; derivedFromIndex?: number })[]
      = accounts.sort((a, b) => (a.derivedFromIndex ?? 0) - (b.derivedFromIndex ?? 0));

      for (const account of sortedAccounts) {
        // We need to remove temporary id and derivedFromIndex from the account to preserve db schema
        const accountToSave = account;
        delete accountToSave.id;
        delete accountToSave.derivedFromIndex;

        const accountId = await addAccount(network, accountToSave);
        account.id = accountId;

        if (!primaryAccountId) {
          primaryAccountId = accountId;
        }
      }

      if (!primaryAccountId) {
        throw new Error('No primary account found');
      }

      void activateAccount(primaryAccountId);

      return sortedAccounts.map((account) => ({
        accountId: account.id!,
        byChain: getAccountChains(account),
      }));
    }))).flat();
  } catch (err) {
    return handleServerError(err);
  }
}

export async function importPrivateKey(
  chain: ApiChain,
  networks: ApiNetwork[],
  privateKey: string,
  password: string,
) {
  const privateKeyEncrypted = await getEncryptedMnemonic([privateKey], password);
  if (typeof privateKeyEncrypted !== 'string') {
    return privateKeyEncrypted;
  }

  return Promise.all(networks.map(async (network) => {
    const wallet = await chains[chain].getWalletFromPrivateKey(network, privateKey);
    const account: ApiBip39Account = {
      type: 'bip39',
      mnemonicEncrypted: privateKeyEncrypted,
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

async function getEncryptedMnemonic(mnemonic: string[], password: string) {
  const mnemonicEncrypted = await encryptMnemonic(mnemonic, password);

  // This is a defensive approach against potential corrupted encryption reported by some users
  const decryptedMnemonic = await decryptMnemonic(mnemonicEncrypted, password)
    .catch(() => undefined);

  if (!password || !decryptedMnemonic) {
    return { error: ApiCommonError.DebugError };
  }

  return mnemonicEncrypted;
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

  await Promise.all([
    deactivateAllAccounts(),
    storage.removeItem('accounts'),
    getEnvironment().isDappSupported && removeAllDapps(),
    tokenRepository.clear(),
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

export async function changePassword(oldPassword: string, password: string) {
  for (const [accountId, account] of Object.entries(await fetchStoredAccounts())) {
    if (!('mnemonicEncrypted' in account)) continue;

    const mnemonic = await decryptMnemonic(account.mnemonicEncrypted, oldPassword);
    const encryptedMnemonic = await encryptMnemonic(mnemonic, password);

    await updateStoredAccount<ApiAccountWithMnemonic>(accountId, {
      mnemonicEncrypted: encryptedMnemonic,
    });
  }
}

export async function upgradeMultichainAccounts(password: string) {
  const supportedChains = getSupportedChains();

  const accounts = await fetchStoredAccounts();

  const accountsToUpgrade = Object.entries(accounts)
    .filter(([, account]) => account.type === 'bip39'
      && supportedChains.some((chain) =>
        !account.byChain?.[chain]?.derivation
        && getChainConfig(chain).isSubwalletsSupported,
      ),
    ) as [string, ApiBip39Account][];

  if (accountsToUpgrade.length) {
    logDebug('Upgrade multichain accounts', accountsToUpgrade.map((e) => e[0]));
  }

  for (const [accountId, account] of accountsToUpgrade) {
    const mnemonic = await getMnemonic(accountId, password, account);

    if (!mnemonic) {
      return { error: ApiCommonError.InvalidPassword };
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      continue;
    }

    const { network } = parseAccountId(accountId);

    for (const chain of supportedChains) {
      if (!getChainConfig(chain).isSubwalletsSupported) {
        continue;
      }

      if (account.byChain?.[chain]?.derivation) {
        continue;
      }

      try {
        const [wallet] = await (chains[chain].getWalletFromBip39Mnemonic as any)(network, mnemonic, undefined, true);

        if (!wallet) {
          continue;
        }

        const fresh = await fetchStoredAccount<ApiBip39Account>(accountId);
        if (fresh.byChain?.[chain]?.derivation) {
          continue;
        }

        await updateStoredAccount<ApiBip39Account>(accountId, {
          byChain: { ...(fresh.byChain ?? {}), [chain]: wallet },
        });

        onUpdate({
          type: 'updateAccount',
          accountId,
          chain,
          address: wallet.address,
          derivation: wallet.derivation,
        });
      } catch (err) {
        logDebugError('upgradeMultichainAccounts: chain failed', { accountId, chain }, err);
      }
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
  const newAccount: ApiAccountWithChain<'ton'> = {
    ...account,
    byChain: {
      ton: ton.getOtherVersionWallet(network, account.byChain.ton, version, isTestnetSubwalletId),
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

  for (let i = 0; i < SETTINGS_SUBWALLET_PAGE_SIZE; i++) {
    const index = offset + i;
    const byChain: ApiGroupedWalletVariant['byChain'] = {};
    let totalBalance = 0n;
    let anyPositive = false;

    for (const chain of getSupportedChains()) {
      const parentWallet = account.byChain[chain];

      if (!parentWallet) continue;

      if (!getChainConfig(chain).isSubwalletsSupported) {
        const balance = await chains[chain].getWalletBalance(network, parentWallet.address);

        totalBalance += balance;

        const { index: _index, ...wallet } = parentWallet;
        byChain[chain] = {
          wallet: wallet as Omit<ApiWalletByChain[typeof chain], 'index'>,
          balance,
          hasDerivation: false,
        };

        continue;
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
      const w = wallets[0];

      if (!w) {
        return { error: ApiCommonError.Unexpected };
      }

      const { index: _wi, ...walletRest } = w;
      const balance = await chains[chain].getWalletBalance(network, walletRest.address);

      totalBalance += balance;
      if (balance > 0n) anyPositive = true;

      byChain[chain] = {
        wallet: walletRest as Omit<ApiWalletByChain[typeof chain], 'index'>,
        balance,
        hasDerivation: true,
      };
    }

    if (!anyPositive || isGroupedVariantSameAsCurrentAccount(account, byChain)) {
      continue;
    }

    pageGroups.push({
      index,
      totalBalance,
      byChain,
    });
  }

  if (page === 0) {
    await maybeMigrateSolanaDerivation(accountId, account, pageGroups);
  }

  return pageGroups;
}

export async function createSubWallet(accountId: string, password: string) {
  try {
    const account = await fetchStoredAccount<ApiBip39Account>(accountId);

    if (account.type !== 'bip39') {
      return { error: ApiCommonError.Unexpected };
    }

    const mnemonic = await getMnemonic(accountId, password, account);

    if (!mnemonic) {
      return { error: ApiCommonError.InvalidPassword };
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return { error: ApiCommonError.Unexpected };
    }

    const { network } = parseAccountId(accountId);
    const stored = await fetchStoredAccounts();

    const siblings = Object.entries(stored).filter(([id, acc]) => {
      if (!('mnemonicEncrypted' in acc)) return false;
      if (acc.mnemonicEncrypted !== account.mnemonicEncrypted) return false;

      return parseAccountId(id).network === network;
    }).map(([, acc]) => acc);

    let maxIndex = -1;

    for (const sib of siblings) {
      for (const chain of Object.keys(sib.byChain) as ApiChain[]) {
        const idx = sib.byChain[chain]?.derivation?.index;

        if (typeof idx === 'number') maxIndex = Math.max(maxIndex, idx);
      }
    }

    const chainKeys = getOrderedAccountChains(account.byChain);
    const hasParentDerivation = chainKeys.some((c) => account.byChain[c]?.derivation);

    if (!hasParentDerivation) {
      return { error: ApiCommonError.Unexpected };
    }

    const newIndex = maxIndex + 1;
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
        ...parentWallet,
        ...wallet,
        index: parentWallet.index,
      } as ApiWalletByChain[typeof chain];
    }

    const duplicateEntry = Object.entries(stored).find(([id, acc]) => {
      if (id === accountId || acc.type === 'view') return false;
      if (!('mnemonicEncrypted' in acc)) return false;
      if (acc.mnemonicEncrypted !== account.mnemonicEncrypted) return false;
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
      mnemonicEncrypted: account.mnemonicEncrypted,
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
    if (!('mnemonicEncrypted' in acc)) return false;
    if (acc.mnemonicEncrypted !== account.mnemonicEncrypted) return false;
    if (parseAccountId(id).network !== network) return false;

    return chainKeys.every((c) => acc.byChain[c]?.address === partialByChain[c]?.address);
  });

  if (duplicate) {
    logDebugError('Duplicate account found', duplicate);

    void activateAccount(duplicate[0]);

    return { isNew: false as const, accountId: duplicate[0] };
  }

  const newByChain: ApiBip39Account['byChain'] = { ...account.byChain };

  for (const chain of chainKeys) {
    const parentWallet = account.byChain[chain]!;
    const newWallet = partialByChain[chain]!;

    (newByChain as Record<ApiChain, ApiWalletByChain[ApiChain]>)[chain] = {
      ...parentWallet,
      ...newWallet,
      index: parentWallet.index,
      publicKey: newWallet.publicKey || parentWallet.publicKey,
    } as ApiWalletByChain[typeof chain]; // merged chain wallet shapes differ per chain
  }

  const newAccountData: ApiBip39Account = {
    type: 'bip39',
    mnemonicEncrypted: account.mnemonicEncrypted,
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

  void activateAccount(newAccountId, undefined, true);

  return {
    isNew: true as const,
    accountId: newAccountId,
    byChain: getAccountChains(newAccountData),
  };
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
