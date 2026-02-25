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
  OnApiUpdate,
} from '../types';
import { ApiCommonError } from '../types';

import { IS_TON_MNEMONIC_ONLY } from '../../config';
import { parseAccountId } from '../../util/account';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { range } from '../../util/iteratees';
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
  version?: ApiTonWalletVersion,
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
        tonWallet = await ton.getWalletFromMnemonic(network, mnemonic, version);
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
        tonWallet ||= await ton.getWalletFromMnemonic(network, mnemonic, version);
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
    .filter(([, account]) => account.type === 'bip39' && !account.byChain.solana) as [string, ApiBip39Account][];

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
    const solanaWallet = await chains.solana.getWalletFromBip39Mnemonic(network, mnemonic);
    const currentAccount = await fetchStoredAccount<ApiBip39Account>(accountId);

    if (currentAccount.type !== 'bip39' || currentAccount.byChain.solana) {
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
    let error: { error: string; chain: ApiChain } | undefined;

    await Promise.all(Object.entries(addressByChain).map(async ([_chain, address]) => {
      // TypeScript emits false notices, because it doesn't see relations between the key and value types in record
      // mapping. We lock the key type to one of the possible values to resolve the TS notices and have at least
      // some type checking.
      const chain = _chain as 'ton';
      const wallet = await chains[chain].getWalletFromAddress(network, address);
      if ('error' in wallet) {
        error = { ...wallet, chain };
        return;
      }

      account.byChain[chain] = wallet.wallet;
      if (wallet.title) title = wallet.title;
    }));

    if (error) return error;

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
  address: string;
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
    address: newAccount.byChain.ton.address,
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
