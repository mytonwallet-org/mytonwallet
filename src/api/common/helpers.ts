import type * as tonSdk from '../chains/ton';
import type { StoredDappsState } from '../dappProtocols/storage';
import type { ApiDbSseConnection } from '../db';
import type { StorageKey } from '../storages/types';
import type {
  ApiActivity,
  ApiLocalTransactionParams,
  ApiTonAccount,
  ApiTonWallet,
  ApiTransactionActivity,
  OnApiUpdate,
} from '../types';

import {
  IS_CAPACITOR, IS_CORE_WALLET, IS_EXTENSION, MAIN_ACCOUNT_ID,
} from '../../config';
import { parseAccountId } from '../../util/account';
import { buildLocalTxId } from '../../util/activities';
import { areDeepEqual } from '../../util/areDeepEqual';
import { assert } from '../../util/assert';
import { logDebugError } from '../../util/logs';
import { toBase64Address } from '../chains/ton/util/tonCore';
import { getEnvironment } from '../environment';
import * as migrations from '../migrations';
import { storage } from '../storages';
import capacitorStorage from '../storages/capacitorStorage';
import idbStorage from '../storages/idb';
import localStorage from '../storages/localStorage';
import {
  checkHasScamLink,
  checkHasTelegramBotMention,
  getKnownAddresses,
  getScamMarkers,
} from './addresses';
import { hexToBytes } from './utils';

const actualStateVersion = 21;

export function buildLocalTransaction(
  params: ApiLocalTransactionParams,
  normalizedAddress: string,
  subId?: number,
): ApiTransactionActivity {
  const id = buildLocalTxId(params.id, subId);

  return updateActivityMetadata({
    // Local transactions are trusted pending
    status: 'pendingTrusted',
    kind: 'transaction',
    timestamp: Date.now(),
    isIncoming: false,
    normalizedAddress,
    ...params,
    amount: -params.amount,
    id,
  });
}

export function updateActivityMetadata<T extends ApiActivity>(activity: T): T {
  if (activity.kind !== 'transaction') {
    return activity;
  }

  const {
    normalizedAddress, comment, isIncoming, type, nft, status,
  } = activity;
  let { metadata = {} } = activity;
  const knownAddresses = getKnownAddresses();
  const hasScamMarkers = comment ? getScamMarkers().some((sm) => sm.test(comment)) : false;
  const isBounced = type === 'bounced';
  const isNft = Boolean(nft);
  const shouldCheckComment = !hasScamMarkers && comment && (isIncoming || isBounced)
    && (isNft || comment.toLowerCase().includes('claim') || isBounced || status === 'failed');
  const hasScamInComment = shouldCheckComment
    ? (checkHasScamLink(comment) || checkHasTelegramBotMention(comment))
    : false;

  if (normalizedAddress in knownAddresses) {
    metadata = { ...metadata, ...knownAddresses[normalizedAddress] };
  }

  if (hasScamMarkers || hasScamInComment) {
    metadata.isScam = true;
  }

  return { ...activity, metadata };
}

let currentOnUpdate: OnApiUpdate | undefined;

export function connectUpdater(onUpdate: OnApiUpdate) {
  currentOnUpdate = onUpdate;
}

export function disconnectUpdater() {
  currentOnUpdate = undefined;
}

export function isUpdaterAlive(onUpdate: OnApiUpdate) {
  return currentOnUpdate === onUpdate;
}

export async function tryMigrateStorage(onUpdate: OnApiUpdate, ton: typeof tonSdk, accountIds?: string[]) {
  try {
    return await migrateStorage(onUpdate, ton, accountIds);
  } catch (err) {
    logDebugError('Migration error', err);
    onUpdate?.({
      type: 'showError',
      error: 'Migration error',
    });
  }
}

export async function migrateStorage(onUpdate: OnApiUpdate, ton: typeof tonSdk, accountIds?: string[]) {
  let version = Number(await storage.getItem('stateVersion', true));

  if (version === actualStateVersion) {
    return;
  }

  if (IS_CORE_WALLET && !version) {
    await migrateCoreWallet(onUpdate);
  }

  if (IS_CAPACITOR && !version) {
    if (await storage.getItem('accounts' as StorageKey, true)) {
      // Fix broken version
      version = 10;
    } else {
      // Prepare for migration to secure storage
      const idbVersion = await idbStorage.getItem('stateVersion');
      if (idbVersion) {
        version = Number(idbVersion);
      }
    }
  }

  // Migration to chrome.storage
  if (IS_EXTENSION && !version && !(await storage.getItem('addresses' as StorageKey))) {
    version = await idbStorage.getItem('stateVersion');

    if (version) {
      // Switching from IndexedDB to `chrome.storage.local`
      const idbData = await idbStorage.getAll!();
      await storage.setMany!(idbData);
    }
  }

  if (!version) {
    await storage.setItem('stateVersion', actualStateVersion);
    return;
  }

  // First version (v1)
  if (!version) {
    // Support multi-accounts
    const mnemonicEncrypted = await storage.getItem('mnemonicEncrypted' as StorageKey);
    if (mnemonicEncrypted) {
      await storage.setItem('mnemonicsEncrypted' as StorageKey, JSON.stringify({
        [MAIN_ACCOUNT_ID]: mnemonicEncrypted,
      }));
      await storage.removeItem('mnemonicEncrypted' as StorageKey);
    }

    // Change accountId format ('0' -> '0-ton', '1-ton-mainnet' -> '1-ton')
    if (!mnemonicEncrypted) {
      for (const field of ['mnemonicsEncrypted', 'addresses', 'publicKeys'] as unknown as StorageKey[]) {
        const raw = await storage.getItem(field);
        if (!raw) continue;

        const oldItem = JSON.parse(raw);

        const newItem = Object.entries(oldItem).reduce((prevValue, [accountId, data]) => {
          const [id, chain = 'ton'] = accountId.split('-');
          const internalAccountId = [id, chain].join('-');
          prevValue[internalAccountId] = data;
          return prevValue;
        }, {} as any);

        await storage.setItem(field, JSON.stringify(newItem));
      }
    }

    version = 1;
    await storage.setItem('stateVersion', version);
  }

  if (version === 1) {
    const addresses = await storage.getItem('addresses' as StorageKey) as string | undefined;
    if (addresses && addresses.includes('-undefined')) {
      for (const field of ['mnemonicsEncrypted', 'addresses', 'publicKeys'] as unknown as StorageKey[]) {
        const newValue = (await storage.getItem(field) as string).replace('-undefined', '-ton');
        await storage.setItem(field, newValue);
      }
    }

    version = 2;
    await storage.setItem('stateVersion', version);
  }

  if (version >= 2 && version <= 4) {
    for (const key of ['addresses', 'mnemonicsEncrypted', 'publicKeys', 'dapps'] as StorageKey[]) {
      const rawData = await storage.getItem(key);
      if (typeof rawData === 'string') {
        await storage.setItem(key, JSON.parse(rawData));
      }
    }

    version = 5;
    await storage.setItem('stateVersion', version);
  }

  if (version === 5) {
    const dapps = await storage.getItem('dapps') as StoredDappsState;
    if (dapps) {
      for (const accountDapps of Object.values(dapps)) {
        for (const dapp of Object.values(accountDapps as Record<string, any>)) {
          dapp.connectedAt = 1;
        }
      }
      await storage.setItem('dapps', dapps);
    }

    version = 6;
    await storage.setItem('stateVersion', version);
  }

  if (version === 6) {
    for (const key of ['addresses', 'mnemonicsEncrypted', 'publicKeys', 'accounts', 'dapps'] as StorageKey[]) {
      let data = await storage.getItem(key) as AnyLiteral;
      if (!data) continue;

      data = Object.entries(data).reduce((byAccountId, [internalAccountId, accountData]) => {
        const parsed = parseAccountId(internalAccountId);
        const mainnetAccountId = buildOldAccountId({ ...parsed, network: 'mainnet' });
        const testnetAccountId = buildOldAccountId({ ...parsed, network: 'testnet' });
        return {
          ...byAccountId,
          [mainnetAccountId]: accountData,
          [testnetAccountId]: accountData,
        };
      }, {} as AnyLiteral);

      await storage.setItem(key, data);
    }

    version = 7;
    await storage.setItem('stateVersion', version);
  }

  if (version === 7) {
    const addresses = (await storage.getItem('addresses' as StorageKey)) as Record<string, string> | undefined;

    if (addresses) {
      const publicKeys = (await storage.getItem('publicKeys' as StorageKey)) as Record<string, string>;
      const accounts = (await storage.getItem('accounts') ?? {}) as Record<string, ApiTonWallet>;

      for (const [accountId, oldAddress] of Object.entries(addresses)) {
        const newAddress = toBase64Address(oldAddress, false);

        accounts[accountId] = {
          ...accounts[accountId],
          address: newAddress,
          publicKey: publicKeys[accountId],
        };

        onUpdate({
          type: 'updateAccount',
          accountId,
          chain: 'ton',
          address: newAddress,
        });
      }

      await storage.setItem('accounts', accounts);

      await storage.removeItem('addresses' as StorageKey);
      await storage.removeItem('publicKeys' as StorageKey);
    }

    version = 8;
    await storage.setItem('stateVersion', version);
  }

  if (version === 8) {
    if (getEnvironment().isSseSupported) {
      const dapps = await storage.getItem('dapps') as StoredDappsState;

      if (dapps) {
        const items: ApiDbSseConnection[] = [];

        for (const accountDapps of Object.values(dapps)) {
          for (const dapp of Object.values(accountDapps as Record<string, any>)) {
            if (dapp.sse?.appClientId) {
              items.push({ clientId: dapp.sse?.appClientId });
            }
          }
        }
      }
    }

    version = 9;
    await storage.setItem('stateVersion', version);
  }

  if (version === 9) {
    if (IS_CAPACITOR) {
      const data = await idbStorage.getAll!();

      for (const [key, value] of Object.entries(data)) {
        await capacitorStorage.setItem(key as StorageKey, value);
        const newValue = await capacitorStorage.getItem(key as StorageKey, true);

        if (!areDeepEqual(value, newValue)) {
          throw new Error('Migration error!');
        }
      }
      await idbStorage.clear();
    }

    version = 10;
    await storage.setItem('stateVersion', version);
  }

  let isIosKeychainModeMigrated = false;
  if (getEnvironment().isIosApp && version >= 10 && version <= 13) {
    await iosBackupAndMigrateKeychainMode();
    isIosKeychainModeMigrated = true;
  }

  if (version === 10 || version === 11 || version === 12) {
    const accounts: Record<string, {
      publicKey: string;
      address: string;
      version?: string;
    }> | undefined = await storage.getItem('accounts', true);

    if (accounts) {
      for (const account of Object.values(accounts)) {
        const { publicKey, address, version: walletVersion } = account;

        if (walletVersion || !publicKey) continue;

        const publicKeyBytes = hexToBytes(publicKey);
        const walletInfo = ton.pickWalletByAddress('mainnet', publicKeyBytes, address);

        account.version = walletInfo.version;
      }

      await storage.setItem('accounts', accounts);
    }

    version = 13;
    await storage.setItem('stateVersion', version);
  }

  if (version === 13) {
    const accounts: Record<string, {
      publicKey: string;
      address: string;
      version?: string;
    }> | undefined = await storage.getItem('accounts', true);

    if (accounts) {
      for (const [accountId, account] of Object.entries(accounts)) {
        const { network } = parseAccountId(accountId);
        if (network === 'testnet') {
          account.address = toBase64Address(account.address, false, network);

          onUpdate({
            type: 'updateAccount',
            accountId,
            chain: 'ton',
            address: account.address,
          });
        }
      }

      version = 14;
      await storage.setItem('accounts', accounts);
    }
  }

  if (version === 14 || version === 15) {
    if (getEnvironment().isIosApp && !isIosKeychainModeMigrated) {
      await iosBackupAndMigrateKeychainMode();
    }

    version = 16;
    await storage.setItem('stateVersion', version);
  }

  if (version === 16) {
    await migrations.migration16.start();

    version = 17;
    await storage.setItem('stateVersion', version);
  }

  if (version === 17) {
    await migrations.migration17.start();

    version = 18;
    await storage.setItem('stateVersion', version);
  }

  if (version === 18) {
    await migrations.migration18.start(accountIds);

    version = 19;
    await storage.setItem('stateVersion', version);
  }

  if (version === 19) {
    await migrations.migration19.start();

    version = 20;
    await storage.setItem('stateVersion', version);
  }

  if (version === 20) {
    await migrations.migration20.start();

    version = 21;
    await storage.setItem('stateVersion', version);
  }
}

function buildOldAccountId(account: { id: number; network: string }) {
  const { id, network } = account;
  return `${id}-ton-${network}`;
}

async function iosBackupAndMigrateKeychainMode() {
  const keys = await capacitorStorage.getKeys();

  if (keys?.length) {
    const items: [string, any][] = [];

    for (const key of keys) {
      if (key.startsWith('backup_')) {
        continue;
      }

      const backupKey = `backup_${key}` as StorageKey;
      const value = await capacitorStorage.getItem(key as StorageKey, true);

      assert(value !== undefined, 'Empty value!');
      await capacitorStorage.setItem(backupKey, value);
      const backupValue = await capacitorStorage.getItem(backupKey);
      assert(areDeepEqual(value, backupValue), 'Data has not been saved!');

      items.push([key, value]);
    }

    for (const [key, value] of items) {
      let shouldRewrite = false;
      await capacitorStorage.setItem(key as StorageKey, value).catch(() => {
        shouldRewrite = true;
      });

      if (shouldRewrite) {
        await capacitorStorage.removeItem(key as StorageKey);
        await capacitorStorage.setItem(key as StorageKey, value);
      }
    }
  }
}

async function migrateCoreWallet(onUpdate: OnApiUpdate) {
  const currentStorage = IS_EXTENSION ? storage : localStorage;

  const [
    // Default Core Wallet version is v3R2
    // https://github.com/toncenter/ton-wallet/blob/master/src/js/Controller.js#L128
    walletVersion = 'v3R2',
    isTestnet,
    address,
    words,
    publicKey,
    isTonProxyEnabled,
  ] = await Promise.all([
    currentStorage.getItem('walletVersion' as StorageKey),
    currentStorage.getItem('isTestnet' as StorageKey),
    currentStorage.getItem('address' as StorageKey),
    currentStorage.getItem('words' as StorageKey),
    currentStorage.getItem('publicKey' as StorageKey),
    currentStorage.getItem('proxy' as StorageKey),
  ]);

  if (isTestnet) {
    onUpdate({
      type: 'updateSettings',
      settings: {
        isTestnet: true,
      },
    });
  }

  const network = isTestnet ? 'testnet' : 'mainnet';
  const accountId = `0-ton-${network}`;

  if (address && words && publicKey) {
    const secondNetwork = network === 'mainnet' ? 'testnet' : 'mainnet';
    const secondAccountId = `0-ton-${secondNetwork}`;
    const secondAddress = toBase64Address(address, false, secondNetwork);

    const newAccountById: Record<string, ApiTonAccount> = {};
    newAccountById[accountId] = {
      type: 'ton',
      mnemonicEncrypted: words,
      byChain: {
        ton: {
          address,
          version: walletVersion,
          publicKey,
          index: 0,
        },
      },
    };

    newAccountById[secondAccountId] = {
      type: 'ton',
      mnemonicEncrypted: words,
      byChain: {
        ton: {
          address: secondAddress,
          version: walletVersion,
          publicKey,
          index: 0,
        },
      },
    };

    await storage.setItem('accounts', newAccountById);

    onUpdate({
      type: 'migrateCoreApplication',
      isTestnet,
      accountId,
      address,
      secondAccountId,
      secondAddress,
      isTonProxyEnabled,
    });

    // Clean up storage after migrate the app from Core Wallet
    [
      'walletVersion', 'isTestnet', 'words', 'address', 'publicKey', 'proxy', 'isLedger',
      'ledgerTransportType', '__time', 'isDebug',
    ].forEach((key) => {
      void currentStorage.removeItem(key as StorageKey);
    });
  }
}
