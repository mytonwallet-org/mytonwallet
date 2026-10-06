import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { StorageKey } from '../storages/types';
import type { OnApiUpdate } from '../types';

import { runStorageMigration } from '../common/helpers';
import { storage } from '../storages';
import { start as migrateAccountChains } from './00019';

const LEGACY_KEYS = ['walletVersion', 'isTestnet', 'address', 'words', 'publicKey'] as const;
const LEGACY_CREDENTIAL_KEYS = ['address', 'words', 'publicKey'] as const;
const TON_WALLET_VERSIONS = new Set<ApiTonWalletVersion>([
  'simpleR1', 'simpleR2', 'simpleR3', 'v2R1', 'v2R2', 'v3R1', 'v3R2', 'v4R2', 'W5',
]);

type LegacyValues = Partial<Record<(typeof LEGACY_KEYS)[number], unknown>>;

export async function hasLegacyCoreStorage() {
  if (await storage.getItem('legacyCoreMigrationCompleted')) return false;
  if (await storage.getItem('legacyCoreAccountsConverted')) return true;
  const values = await readLegacyValues();
  return LEGACY_CREDENTIAL_KEYS.some((key) => values[key] !== undefined);
}

export function confirmLegacyCoreMigration() {
  return storage.setItem('legacyCoreMigrationCompleted', true);
}

export function retireLegacyCoreMigration(accountId?: string) {
  if (accountId !== undefined && accountId !== '0-ton-mainnet' && accountId !== '0-ton-testnet') {
    return Promise.resolve();
  }

  return runStorageMigration(async () => {
    const values = await readLegacyValues();
    const hasCredentials = LEGACY_CREDENTIAL_KEYS.some((key) => values[key] !== undefined);
    if (!hasCredentials && !await hasLegacyCoreStorage()) return;
    const network = values.isTestnet === true ? 'testnet' : 'mainnet';
    if (accountId !== undefined && accountId !== `0-ton-${network}`) return;

    for (const key of LEGACY_CREDENTIAL_KEYS) {
      await storage.removeItem(key as StorageKey);
    }
    await confirmLegacyCoreMigration();
  });
}

export async function classifyVersionedLegacyCoreStorage() {
  await storage.setItem('legacyCoreMigrationCompleted', true);
}

export async function startLegacyCoreMigration(onUpdate: OnApiUpdate) {
  const values = await readLegacyValues();
  const network = values.isTestnet === true ? 'testnet' : 'mainnet';
  const accountId = `0-ton-${network}`;
  const areAccountsConverted = await storage.getItem('legacyCoreAccountsConverted') === true;
  if (!areAccountsConverted) {
    if (!LEGACY_CREDENTIAL_KEYS.some((key) => values[key] !== undefined)) return false;
    const walletVersion = values.walletVersion ?? 'v3R2';
    const { address, words, publicKey } = values;
    if (
      typeof address !== 'string' || !address
      || typeof words !== 'string' || !words
      || typeof publicKey !== 'string' || !publicKey
      || typeof walletVersion !== 'string' || !TON_WALLET_VERSIONS.has(walletVersion as ApiTonWalletVersion)
      || (values.isTestnet !== undefined && typeof values.isTestnet !== 'boolean')
    ) {
      throw new Error('Incomplete legacy Core Wallet storage');
    }

    const expected = buildAccount(address, publicKey, words, walletVersion as ApiTonWalletVersion);
    const accounts = await storage.getItem('accounts') as Record<string, AnyLiteral> | undefined;
    const existing = accounts?.[accountId];
    if (existing && !isSameLegacyAccount(existing, expected)) {
      throw new Error(`Legacy Core Wallet conflicts with account ${accountId}`);
    }
    if (!existing) {
      await storage.setItem('accounts', { ...accounts, [accountId]: expected });
    }
    await migrateAccountChains();
    await storage.setItem('legacyCoreAccountsConverted', true);
  }

  const accounts = await storage.getItem('accounts') as Record<string, AnyLiteral>;
  if (!accounts?.[accountId]) throw new Error(`Missing converted Core Wallet account ${accountId}`);
  const uiAccounts = Object.entries(accounts).map(([id, account]) => {
    const ton = account.byChain?.ton;
    if (account.type !== 'ton' || typeof ton?.address !== 'string' || !ton.address
      || Object.keys(account.byChain).length !== 1) {
      throw new Error(`Unsupported legacy Core Wallet account ${id}`);
    }
    return { accountId: id, address: ton.address };
  });

  onUpdate({
    type: 'migrateLegacyCoreApplication',
    accounts: uiAccounts,
    currentAccountId: accountId,
  });

  return true;
}

async function readLegacyValues(): Promise<LegacyValues> {
  return storage.getMany!(LEGACY_KEYS as unknown as string[]) as Promise<LegacyValues>;
}

function buildAccount(
  address: string,
  publicKey: string,
  mnemonicEncrypted: string,
  version: ApiTonWalletVersion,
) {
  return {
    type: 'ton',
    mnemonicEncrypted,
    byChain: { ton: { address, publicKey, index: 0, version } },
  };
}

function isSameLegacyAccount(existing: AnyLiteral, expected: AnyLiteral) {
  const existingTon = existing.byChain?.ton ?? existing.ton;
  const expectedTon = expected.byChain.ton;
  return existing.type === 'ton'
    && (existing.mnemonicEncrypted === undefined || existing.mnemonicEncrypted === expected.mnemonicEncrypted)
    && existingTon?.address === expectedTon.address
    && existingTon?.publicKey === expectedTon.publicKey
    && existingTon?.index === expectedTon.index
    && existingTon?.version === expectedTon.version;
}
