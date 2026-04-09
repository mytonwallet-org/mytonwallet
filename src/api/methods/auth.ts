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
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { range } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { createTaskQueue } from '../../util/schedulers';
import chains from '../chains';
import { SOLANA_DERIVATION_PATHS } from '../chains/solana/constants';
import { extractIndexFromPath } from '../chains/solana/wallet';
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
    return await Promise.all(networks.map(async (network) => {
      let account: ApiAccountWithMnemonic;
      let tonWallet: ApiTonWallet & { lastTxId?: string } | undefined;
      let shouldForceTonMnemonic = false;

      if (isBip39Mnemonic && isTonMnemonic) {
        tonWallet = await ton.getWalletFromMnemonic(network, mnemonic);
        if (tonWallet.lastTxId) {
          shouldForceTonMnemonic = true;
        }
      }

      if (isBip39Mnemonic && !shouldForceTonMnemonic) {
        account = {
          type: 'bip39',
          mnemonicEncrypted,
          byChain: {},
        };

        await Promise.all((Object.keys(chains) as (keyof typeof chains)[]).map(async (_chain) => {
          // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
          // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
          // some type checking.
          const chain = _chain as 'ton';
          account.byChain[chain] = await chains[chain].getWalletFromBip39Mnemonic(network, mnemonic);
        }));
      } else {
        tonWallet ||= await ton.getWalletFromMnemonic(network, mnemonic);
        account = {
          type: 'ton',
          mnemonicEncrypted,
          byChain: {
            ton: tonWallet,
          },
        };
      }

      const accountId = await addAccount(network, account);
      void activateAccount(accountId);

      return {
        accountId,
        byChain: getAccountChains(account),
      };
    }));
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
  const accountsToUpgrade = Object.entries(await fetchStoredAccounts())
    .filter(([, account]) =>
      account.type === 'bip39' && (!account.byChain.solana || !account.byChain.solana.derivation),
    ) as [string, ApiBip39Account][];

  if (accountsToUpgrade.length) {
    logDebug('Upgrade multichain accounts', accountsToUpgrade);
  }

  const updates: {
    accountId: string;
    address: string;
  }[] = [];

  for (const [accountId, account] of accountsToUpgrade) {
    const mnemonic = await getMnemonic(accountId, password, account);
    if (!mnemonic) {
      return { error: ApiCommonError.InvalidPassword };
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      continue;
    }

    const { network } = parseAccountId(accountId);
    const solanaWallet = await (chains.solana.getWalletFromBip39Mnemonic as any)(network, mnemonic, true);
    const currentAccount = await fetchStoredAccount<ApiBip39Account>(accountId);

    if (currentAccount.type !== 'bip39'
      || (currentAccount.byChain.solana && currentAccount.byChain.solana.derivation)
    ) {
      continue;
    }

    await updateStoredAccount<ApiBip39Account>(accountId, {
      byChain: {
        ...currentAccount.byChain,
        solana: solanaWallet,
      },
    });

    onUpdate({
      type: 'updateAccount',
      accountId,
      chain: 'solana',
      address: solanaWallet.address,
      derivation: solanaWallet.derivation,
    });

    updates.push({
      accountId,
      address: solanaWallet.address,
    });
  }

  return updates;
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

export async function getWalletVariants(
  network: ApiNetwork,
  chain: ApiChain,
  accountId: string,
  page: number,
  isTestnetSubwalletId?: boolean,
  mnemonic?: string[],
) {
  const account = await fetchStoredChainAccount(accountId, chain);

  const chainVariants = await chains[chain].getWalletVariants(
    network,
    account,
    page,
    isTestnetSubwalletId,
    mnemonic,
  );

  if ('error' in chainVariants) {
    return chainVariants;
  }

  const solanaAccount = account.byChain.solana;

  if (
    chain === 'solana'
    && solanaAccount?.address
    && !solanaAccount.derivation
    && mnemonic
  ) {
    const match = chainVariants.find((variant) => {
      return variant.wallet.address === solanaAccount.address
        && variant.metadata?.type === 'path';
    });

    if (match && match.metadata?.type === 'path') {
      const path = match.wallet.derivation?.path || SOLANA_DERIVATION_PATHS.phantom;
      const index = extractIndexFromPath(path);
      const label = match.wallet.derivation?.label;

      await updateStoredWallet(accountId, 'solana', {
        derivation: { path, index, label },
      });
    }
  }

  return chainVariants;
}

export async function createSubWallet<T extends ApiChain>(
  chain: T,
  accountId: string,
  password: string,
) {
  const account = await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);

  if (!('mnemonicEncrypted' in account)) {
    return { error: ApiCommonError.Unexpected };
  }

  const wallet = account.byChain[chain];

  if (!wallet || !wallet.derivation) {
    return { error: ApiCommonError.Unexpected };
  }

  const mnemonic = await getMnemonic(accountId, password, account);
  if (!mnemonic) {
    return { error: ApiCommonError.InvalidPassword };
  }

  const { network } = parseAccountId(accountId);

  const newWallet = await chains[chain].createSubWalletFromDerivation(
    network,
    account as ApiAccountWithChain<typeof chain>,
    mnemonic,
  );

  if (!newWallet || 'error' in newWallet) {
    return newWallet;
  }

  const accounts = await fetchStoredAccounts();

  const duplicate = Object.entries(accounts).find(
    ([id, acc]) => id !== accountId
      && acc.byChain[chain]?.address === newWallet.address
      && acc.type !== 'view',
  );

  if (duplicate) {
    logDebugError('Duplicate account found', duplicate);

    return { isNew: false as const, accountId: duplicate[0] };
  }

  const newAccountData = {
    ...account,
    byChain: {
      ...account.byChain,
      [chain]: newWallet,
    },
  };
  const newAccountId = await addAccount(network, newAccountData);

  onUpdate({
    type: 'updateAccount',
    accountId: newAccountId,
    chain,
    address: newWallet.address,
    derivation: newWallet.derivation,
  });

  void activateAccount(newAccountId, undefined, true);

  return {
    isNew: true as const,
    address: newWallet.address,
    derivation: newWallet.derivation,
    accountId: newAccountId,
    byChain: getAccountChains(newAccountData),
  };
}

export async function addSubWallet(
  chain: ApiChain,
  accountId: string,
  newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>,
  isReplace: boolean,
) {
  const account = await fetchStoredChainAccount(accountId, chain);

  const accounts = await fetchStoredAccounts();

  const duplicate = Object.entries(accounts).find(
    ([id, acc]) => id !== accountId
      && acc.byChain[chain]?.address === newWallet.address
      && acc.type !== 'view',
  );

  if (duplicate) {
    logDebugError('Duplicate account found', duplicate);

    return { isNew: false as const, accountId: duplicate[0] };
  }

  if (!isReplace) {
    const { network } = parseAccountId(accountId);
    const newAccount: ApiAccountAny = {
      ...account,
      byChain: {
        ...account.byChain,
        [chain]: {
          ...newWallet,
          index: account.byChain[chain].index,
          publicKey: newWallet.publicKey || account.byChain[chain].publicKey,
        },
      },
    };
    const newAccountId = await addAccount(network, newAccount);

    onUpdate({
      type: 'updateAccount',
      accountId: newAccountId,
      chain,
      address: newWallet.address,
    });

    void activateAccount(newAccountId);

    return {
      isNew: true as const,
      address: newWallet.address,
      accountId: newAccountId,
      byChain: getAccountChains(newAccount),
    };
  }

  await updateStoredAccount(accountId, {
    byChain: { ...account.byChain, [chain]: {
      ...newWallet,
      index: account.byChain[chain].index,
      publicKey: newWallet.publicKey || account.byChain[chain].publicKey,
    } },
  });

  onUpdate({
    type: 'updateAccount',
    accountId,
    chain,
    address: newWallet.address,
    derivation: newWallet.derivation,
  });

  void activateAccount(accountId);

  return { isNew: false as const, accountId };
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
