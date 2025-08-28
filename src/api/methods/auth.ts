import type { GlobalState } from '../../global/types';
import type { LedgerWalletInfo } from '../../util/ledger/types';
import type { ApiTonWalletVersion } from '../chains/ton/types';
import type {
  ApiAccountAny,
  ApiAccountWithMnemonic,
  ApiActivityTimestamps,
  ApiImportAddressByChain,
  ApiLedgerDriver,
  ApiNetwork,
  ApiTonAccount,
  ApiTonWallet,
  ApiViewAccount,
} from '../types';
import { ApiCommonError } from '../types';

import { DEFAULT_WALLET_VERSION, IS_BIP39_MNEMONIC_ENABLED, IS_CORE_WALLET } from '../../config';
import { parseAccountId } from '../../util/account';
import isMnemonicPrivateKey from '../../util/isMnemonicPrivateKey';
import { createTaskQueue } from '../../util/schedulers';
import chains from '../chains';
import { getWalletFromKeys } from '../chains/ton/auth';
import { toBase64Address } from '../chains/ton/util/tonCore';
import {
  fetchStoredAccounts,
  fetchStoredTonAccount,
  getAddressesFromAccount,
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

const { ton, tron } = chains;

export function generateMnemonic(isBip39: boolean) {
  if (isBip39) return generateBip39Mnemonic();
  return ton.generateMnemonic();
}

export function createWallet(
  network: ApiNetwork,
  mnemonic: string[],
  password: string,
  version?: ApiTonWalletVersion,
) {
  if (!version) version = DEFAULT_WALLET_VERSION;

  return importMnemonic(network, mnemonic, password, version);
}

export function validateMnemonic(mnemonic: string[]) {
  return (validateBip39Mnemonic(mnemonic) && IS_BIP39_MNEMONIC_ENABLED) || chains.ton.validateMnemonic(mnemonic);
}

export async function importMnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  password: string,
  version?: ApiTonWalletVersion,
) {
  const isPrivateKey = isMnemonicPrivateKey(mnemonic);
  let isBip39Mnemonic = validateBip39Mnemonic(mnemonic);
  const isTonMnemonic = await ton.validateMnemonic(mnemonic);

  if (!isPrivateKey && !isTonMnemonic && (!isBip39Mnemonic || !IS_BIP39_MNEMONIC_ENABLED)) {
    throw new Error('Invalid mnemonic');
  }

  const mnemonicEncrypted = await encryptMnemonic(mnemonic, password);

  // This is a defensive approach against potential corrupted encryption reported by some users
  const decryptedMnemonic = await decryptMnemonic(mnemonicEncrypted, password)
    .catch(() => undefined);

  if (!password || !decryptedMnemonic) {
    return { error: ApiCommonError.DebugError };
  }

  let account: ApiAccountAny;
  let tonWallet: ApiTonWallet & { lastTxId?: string } | undefined;

  try {
    if (isBip39Mnemonic && isTonMnemonic) {
      tonWallet = await ton.getWalletFromMnemonic(mnemonic, network, version);
      if (tonWallet.lastTxId) {
        isBip39Mnemonic = false;
      }
    }

    if (isBip39Mnemonic) {
      const tronWallet = tron.getWalletFromBip39Mnemonic(network, mnemonic);
      tonWallet = await ton.getWalletFromBip39Mnemonic(network, mnemonic);

      account = {
        type: 'bip39',
        mnemonicEncrypted,
        tron: tronWallet,
        ton: tonWallet,
      };
    } else {
      if (!tonWallet) {
        tonWallet = isPrivateKey
          ? await ton.getWalletFromPrivateKey(mnemonic[0], network, version)
          : await ton.getWalletFromMnemonic(mnemonic, network, version);
      }
      account = {
        type: 'ton',
        mnemonicEncrypted,
        ton: tonWallet,
      };
    }

    const accountId = await addAccount(network, account);
    const secondNetworkAccount = IS_CORE_WALLET ? await createAccountWithSecondNetwork({
      accountId, network, mnemonic, mnemonicEncrypted, version,
    }) : undefined;
    void activateAccount(accountId);

    return {
      accountId,
      addressByChain: getAddressesFromAccount(account),
      secondNetworkAccount,
    };
  } catch (err) {
    return handleServerError(err);
  }
}

export async function createAccountWithSecondNetwork(options: {
  accountId: string;
  network: ApiNetwork;
  mnemonic: string[];
  mnemonicEncrypted: string;
  version?: ApiTonWalletVersion;
}): Promise<GlobalState['auth']['secondNetworkAccount']> {
  const {
    mnemonic, version, mnemonicEncrypted,
  } = options;
  const { network, accountId } = options;
  const tonWallet = await ton.getWalletFromMnemonic(mnemonic, network, version);

  const secondNetwork = network === 'testnet' ? 'mainnet' : 'testnet';
  tonWallet.address = toBase64Address(tonWallet.address, false, secondNetwork);
  const account: ApiTonAccount = {
    type: 'ton',
    mnemonicEncrypted,
    ton: tonWallet,
  };
  const secondAccountId = await addAccount(secondNetwork, account, parseAccountId(accountId).id);

  return {
    accountId: secondAccountId,
    addressByChain: { ton: tonWallet.address },
    network: secondNetwork,
  };
}

export function addressFromPublicKey(
  publicKey: Uint8Array,
  network: ApiNetwork,
  version?: ApiTonWalletVersion,
): Promise<ApiTonWallet & { lastTxId?: string }> {
  return getWalletFromKeys(publicKey, network, version);
}

export async function importLedgerWallet(network: ApiNetwork, walletInfo: LedgerWalletInfo) {
  const {
    publicKey, address, index, driver, deviceId, deviceName, version,
  } = walletInfo;

  const accountId = await addAccount(network, {
    type: 'ledger',
    ton: {
      type: 'ton',
      address,
      publicKey,
      version,
      index,
    },
    driver,
    deviceId,
    deviceName,
  });

  return { accountId, address, walletInfo };
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
  nextAccountId: string,
  newestActivityTimestamps?: ApiActivityTimestamps,
) {
  removePollingAccount(accountId);

  await Promise.all([
    removeAccountValue(accountId, 'accounts'),
    getEnvironment().isDappSupported && removeAccountDapps(accountId),
  ]);

  await activateAccount(nextAccountId, newestActivityTimestamps);
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

export async function importViewAccount(network: ApiNetwork, addressByChain: ApiImportAddressByChain) {
  try {
    const account: ApiViewAccount = {
      type: 'view',
    };
    let title: string | undefined;

    if (addressByChain.ton) {
      const wallet = await ton.getWalletFromAddress(network, addressByChain.ton);
      if ('error' in wallet) return { ...wallet, chain: 'ton' };
      account.ton = wallet.wallet;
      title = wallet.title;
    }

    if (addressByChain.tron) {
      account.tron = {
        type: 'tron',
        address: addressByChain.tron,
        index: 0,
      };
    }

    const accountId = await addAccount(network, account);
    void activateAccount(accountId);

    return {
      accountId,
      title,
      resolvedAddresses: getAddressesFromAccount(account),
    };
  } catch (err) {
    return handleServerError(err);
  }
}

export async function importNewWalletVersion(accountId: string, version: ApiTonWalletVersion): Promise<{
  isNew: true;
  accountId: string;
  address: string;
  ledger?: { index: number; driver: ApiLedgerDriver };
} | {
  isNew: false;
  accountId: string;
}> {
  const { network } = parseAccountId(accountId);
  const account = await fetchStoredTonAccount(accountId);
  const newAccount = {
    ...account,
    ton: ton.getOtherVersionWallet(network, account.ton, version),
  };

  const accounts = await fetchStoredAccounts();
  const existingAccount = Object.entries(accounts).find(([, account]) => {
    return account.ton?.address === newAccount.ton.address && account.type === newAccount.type;
  });

  if (existingAccount) {
    return {
      isNew: false,
      accountId: existingAccount[0],
    };
  }

  const ledger = account.type === 'ledger'
    ? { index: account.ton.index, driver: account.driver }
    : undefined;

  const newAccountId = await addAccount(network, newAccount);

  return {
    isNew: true,
    accountId: newAccountId,
    address: newAccount.ton.address,
    ledger,
  };
}
