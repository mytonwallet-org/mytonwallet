import { HDNodeWallet, Mnemonic, Wallet } from 'ethers';

import type {
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiAnyDisplayError,
  ApiDerivation,
  ApiEVMWallet,
  ApiNetwork,
  ApiWalletByChain,
  ApiWalletVariant,
  EVMChain,
} from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { fetchStoredAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex } from '../../common/utils';
import { isValidAddress } from './address';
import { EVM_DERIVATION_PATHS } from './constants';
import { getWalletBalance, getWalletLastTransaction } from './wallet';

const MULTIWALLET_BY_PATH_DEFAULT_COUNT = 2;
const WALLET_DERIVATIONS_BATCH_SIZE = 6;
const SETTINGS_MULTIWALLET_BY_PATH_COUNT = 4;
const MAX_NON_EMPTY_WALLETS_TO_SCAN = 20;

type EvmWalletRaw = {
  address: string;
  publicKey: string;
  privateKeyBytes: Uint8Array;
  path: string;
  label?: string;
  index: number;
};

function createWalletFromPrivateKey(privateKeyBytes: Uint8Array): EvmWalletRaw {
  const wallet = new Wallet(bytesToHex(privateKeyBytes));

  return {
    address: wallet.address,
    publicKey: wallet.signingKey.compressedPublicKey,
    privateKeyBytes,
    path: EVM_DERIVATION_PATHS.default,
    index: 0,
  };
}

function getWalletVariantForPath(
  mnemonic: Mnemonic,
  pathTemplate: string,
  index: number,
  label?: string,
): EvmWalletRaw {
  const path = pathTemplate.includes('{index}')
    ? pathTemplate.replace('{index}', String(index))
    : pathTemplate;

  const hdNode = HDNodeWallet.fromMnemonic(mnemonic, path);
  const privateKeyBytes = new Uint8Array(Buffer.from(hdNode.privateKey.slice(2), 'hex'));

  return {
    address: hdNode.address,
    publicKey: hdNode.signingKey.compressedPublicKey,
    privateKeyBytes,
    path: pathTemplate,
    index,
    label,
  };
}

export async function fetchPrivateKeyString(
  chain: EVMChain,
  accountId: string,
  password: string,
  account?: ApiAccountWithMnemonic,
) {
  try {
    account = account ?? (await fetchStoredAccount<ApiAccountWithMnemonic>(accountId));
    const mnemonic = await getMnemonic(accountId, password, account);
    if (!mnemonic) {
      return undefined;
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return mnemonic[0];
    }

    const { network } = parseAccountId(accountId);

    const derivation = account.byChain[chain]?.derivation;

    const raw = await getRawWalletFromBip39Mnemonic(network, chain, mnemonic, derivation);

    return bytesToHex(raw.privateKeyBytes);
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);
    return undefined;
  }
}

export async function getWalletFromBip39Mnemonic(
  chain: EVMChain,
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
  isMigration?: boolean,
): Promise<ApiEVMWallet[]> {
  const phrase = mnemonic.join(' ');
  const mnemonicObj = Mnemonic.fromPhrase(phrase);

  if (derivation) {
    const raw = getWalletVariantForPath(
      mnemonicObj,
      derivation.path,
      derivation.index,
      derivation.label,
    );

    return [{
      address: raw.address,
      publicKey: raw.publicKey,
      index: 0,
      derivation: { path: raw.path, index: raw.index, label: raw.label },
    }];
  }

  const raws = await pickBestWallets(network, chain, mnemonicObj, isMigration);

  return raws.map((raw) => ({
    address: raw.address,
    publicKey: raw.publicKey,
    index: 0,
    derivation: { path: raw.path, index: raw.index, label: raw.label },
  }));
}

export function getWalletFromPrivateKey(network: ApiNetwork, privateKey: string): ApiEVMWallet {
  const privateKeyBytes = new Uint8Array(Buffer.from(privateKey.replace(/^0x/, ''), 'hex'));
  const raw = createWalletFromPrivateKey(privateKeyBytes);

  return {
    address: raw.address,
    publicKey: raw.publicKey,
    index: 0,
  };
}

export function getSignerFromPrivateKey(network: ApiNetwork, privateKey: string): Wallet {
  return new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);
}

export function getWalletFromAddress(
  network: ApiNetwork,
  addressOrDomain: string,
): { title?: string; wallet: ApiEVMWallet } | { error: ApiAnyDisplayError } {
  if (!isValidAddress(addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    title: getKnownAddressInfo(addressOrDomain)?.name,
    wallet: {
      address: addressOrDomain,
      index: 0,
    },
  };
}

export async function createSubWalletFromDerivation<C extends EVMChain>(
  chain: C,
  network: ApiNetwork,
  account: ApiAccountWithChain<C>,
  mnemonic: string[],
): Promise<ApiEVMWallet | { error: ApiAnyDisplayError }> {
  const current = account.byChain[chain];
  if (!current) {
    return { error: ApiCommonError.Unexpected };
  }

  const { derivation } = current;

  const defaultLabel = 'default';

  const pathTemplate = derivation?.path ?? EVM_DERIVATION_PATHS[defaultLabel];
  const startIndex = derivation?.index ?? 0;

  const mnemonicObj = Mnemonic.fromPhrase(mnemonic.join(' '));

  let offset = startIndex + 1;
  let scannedNonEmptyWallets = 0;

  let emptySubwallet: EvmWalletRaw | undefined;

  while (emptySubwallet === undefined) {
    const batch = Array.from({ length: SETTINGS_MULTIWALLET_BY_PATH_COUNT }, (_, indexInBatch) =>
      getWalletVariantForPath(
        mnemonicObj,
        pathTemplate,
        offset + indexInBatch,
        derivation?.label ?? defaultLabel,
      ));

    const balances = await Promise.all(batch.map(({ address: addr }) => getWalletBalance(chain, network, addr)));

    for (const [i, subwallet] of batch.entries()) {
      if (balances[i] === 0n) {
        emptySubwallet = subwallet;
        break;
      }

      scannedNonEmptyWallets += 1;
      if (scannedNonEmptyWallets >= MAX_NON_EMPTY_WALLETS_TO_SCAN) {
        break;
      }
    }

    if (scannedNonEmptyWallets >= MAX_NON_EMPTY_WALLETS_TO_SCAN) {
      break;
    }

    offset += SETTINGS_MULTIWALLET_BY_PATH_COUNT;

    if (emptySubwallet === undefined) {
      await pause(500);
    }
  }

  if (emptySubwallet === undefined) {
    return { error: ApiCommonError.Unexpected };
  }

  return {
    address: emptySubwallet.address,
    publicKey: emptySubwallet.publicKey,
    index: current.index,
    derivation: {
      path: pathTemplate,
      index: emptySubwallet.index,
      label: derivation?.label ?? defaultLabel,
    },
  };
}

async function getRawWalletFromBip39Mnemonic(
  network: ApiNetwork,
  chain: EVMChain,
  mnemonic: string[],
  derivation?: ApiDerivation,
  isMigration?: boolean,
): Promise<EvmWalletRaw> {
  const phrase = mnemonic.join(' ');

  const mnemonicObj = Mnemonic.fromPhrase(phrase);

  if (derivation) {
    return getWalletVariantForPath(mnemonicObj, derivation.path, derivation.index, derivation.label);
  }

  return await pickBestWallet(network, chain, mnemonicObj, isMigration);
}

/**
 * BIP44 path variants with balance (like Solana), or all scanned variants if none, or default only for migration.
 */
async function pickBestWallets(
  network: ApiNetwork,
  chain: EVMChain,
  mnemonic: Mnemonic,
  isMigration?: boolean,
): Promise<EvmWalletRaw[]> {
  const variants = getWalletVariantsByPath(mnemonic);

  const defaultWallet = variants.find((v) => v.path === EVM_DERIVATION_PATHS.default);
  if (!defaultWallet) {
    throw new Error('EVM: no wallet variants');
  }

  if (isMigration) {
    return [defaultWallet];
  }

  const withBalances = await Promise.all(
    variants.map(async (v) => ({
      ...v,
      balance: await getWalletBalance(chain, network, v.address),
    })),
  );

  const withPositive = withBalances.filter((v) => v.balance > 0n);

  if (withPositive.length > 0) {
    return withPositive.map(({ balance, ...v }) => v);
  }

  return [defaultWallet];
}

function getWalletVariantsByPath(
  mnemonic: Mnemonic,
  count: number = MULTIWALLET_BY_PATH_DEFAULT_COUNT,
  offset: number = 0,
): EvmWalletRaw[] {
  return Object.entries(EVM_DERIVATION_PATHS).flatMap(([label, pathTemplate]) => {
    const hasIndexPlaceholder = pathTemplate.includes('{index}');
    const iterations = hasIndexPlaceholder ? count : 1;

    const acc: EvmWalletRaw[] = [];

    for (let i = 0; i < iterations; i++) {
      const index = offset + i;
      acc.push(getWalletVariantForPath(mnemonic, pathTemplate, index, label));
    }

    return acc;
  });
}

export async function getWalletVariants<C extends EVMChain>(
  chain: C,
  network: ApiNetwork,
  account: ApiAccountWithChain<C>,
  page: number,
  isTestnetSubwalletId?: boolean,
  mnemonic?: string[],
): Promise<ApiWalletVariant<C>[] | { error: ApiAnyDisplayError }> {
  if (!mnemonic?.length) {
    return { error: ApiCommonError.Unexpected };
  }

  const mnemonicObj = Mnemonic.fromPhrase(mnemonic.join(' '));

  const offset = page * SETTINGS_MULTIWALLET_BY_PATH_COUNT;

  const variants = getWalletVariantsByPath(mnemonicObj, SETTINGS_MULTIWALLET_BY_PATH_COUNT, offset);

  const addressesWithBalances: (EvmWalletRaw & { balance: bigint })[] = [];
  const batches = [];

  for (let i = 0; i < variants.length; i += WALLET_DERIVATIONS_BATCH_SIZE) {
    batches.push(variants.slice(i, i + WALLET_DERIVATIONS_BATCH_SIZE));
  }

  for (const batch of batches) {
    const results = await Promise.all(
      batch.map(async (v) => ({
        ...v,
        balance: await getWalletBalance(chain, network, v.address),
      })),
    );
    addressesWithBalances.push(...results);
    await pause(500);
  }

  return addressesWithBalances.map((v) => ({
    chain,
    wallet: {
      address: v.address,
      publicKey: v.publicKey,
      derivation: {
        path: v.path,
        index: v.index,
        label: v.label,
      },
    } as Omit<ApiWalletByChain[C], 'index'>,
    balance: v.balance,
    metadata: {
      type: 'path',
      path: v.path.replace('{index}', v.index.toString()),
      label: v.label,
    },
  }));
}

export async function pickBestWallet(
  network: ApiNetwork,
  chain: EVMChain,
  mnemonic: Mnemonic,
  isMigration?: boolean,
): Promise<EvmWalletRaw> {
  const variants = getWalletVariantsByPath(mnemonic);

  const defaultWallet
    = variants.find((v) => v.path === EVM_DERIVATION_PATHS.default)!;

  if (isMigration) {
    return defaultWallet;
  }

  const withBalances = await Promise.all(
    variants.map(async (v) => ({
      ...v,
      balance: await getWalletBalance(chain, network, v.address),
    })),
  );

  const bestByBalance = withBalances.reduce<(typeof withBalances)[0] | undefined>(
    (best, cur) => (cur.balance > (best?.balance ?? 0n) ? cur : best),
  undefined,
  );

  if (bestByBalance && bestByBalance.balance > 0n) {
    return bestByBalance;
  }

  await pause(500);

  const withLastTx = await Promise.all(
    variants.map(async (v) => {
      const last = await getWalletLastTransaction(network, v.address) as { blockTime?: number } | undefined;
      return { ...v, lastTxBlock: last?.blockTime };
    }),
  );

  const bestByLastTx = withLastTx.reduce<(typeof withLastTx)[0] | undefined>(
    (best, cur) =>
      cur.lastTxBlock !== undefined && (best?.lastTxBlock ?? 0) < cur.lastTxBlock ? cur : best,
  undefined,
  );

  if (bestByLastTx) {
    return bestByLastTx;
  }

  if (!defaultWallet) {
    throw new Error('EVM: no wallet variants');
  }

  return defaultWallet;
}
