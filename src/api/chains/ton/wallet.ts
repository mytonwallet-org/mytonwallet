import { beginCell, Cell, storeStateInit } from '@ton/core';
import type { WalletContractV5R1 } from '@ton/ton';

import type {
  ApiAnyDisplayError,
  ApiNetwork,
  ApiTonWallet,
  ApiWalletInfo,
  ApiWalletWithVersionInfo,
} from '../../types';
import type { ApiTonWalletVersion, ContractInfo } from './types';
import type { TonWallet } from './util/tonCore';

import { DEFAULT_WALLET_VERSION, TONCOIN } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { extractKey, findLast } from '../../../util/iteratees';
import withCacheAsync from '../../../util/withCacheAsync';
import {
  getTonClient, toBase64Address, walletClassMap,
} from './util/tonCore';
import { fetchStoredWallet } from '../../common/accounts';
import { base64ToBytes, hexToBytes, sha256 } from '../../common/utils';
import { ALL_WALLET_VERSIONS, ContractType, KnownContracts, NETWORK_CONFIG, WORKCHAIN } from './constants';
import { loadTokenBalances } from './tokens';
import { fetchJettonWallets } from './tokens';
import { getWalletInfos } from './toncenter';

export const isAddressInitialized = withCacheAsync(
  async (network: ApiNetwork, walletOrAddress: TonWallet | string) => {
    return (await getWalletInfo(network, walletOrAddress)).isInitialized;
  },
);

export const isActiveSmartContract = withCacheAsync(async (network: ApiNetwork, address: string) => {
  const { isInitialized, version } = await getWalletInfo(network, address);
  return isInitialized ? !version : undefined;
}, (value) => value !== undefined);

export function publicKeyToAddress(
  network: ApiNetwork,
  publicKey: Uint8Array,
  walletVersion: ApiTonWalletVersion,
  isTestnetSubwalletId?: boolean,
) {
  const wallet = buildWallet(publicKey, walletVersion, isTestnetSubwalletId);
  return toBase64Address(wallet.address, false, network);
}

export function buildWallet(
  publicKey: Uint8Array | string,
  walletVersion: ApiTonWalletVersion,
  isTestnetSubwalletId?: boolean,
): TonWallet {
  if (typeof publicKey === 'string') {
    publicKey = hexToBytes(publicKey);
  }

  const WalletClass = walletClassMap[walletVersion];
  if (!WalletClass) {
    throw new Error(`Unsupported wallet contract version "${walletVersion}"`);
  }

  if (walletVersion === 'W5') {
    return (WalletClass as typeof WalletContractV5R1).create({
      publicKey: Buffer.from(publicKey),
      workchain: WORKCHAIN,
      walletId: {
        networkGlobalId: NETWORK_CONFIG[isTestnetSubwalletId ? 'testnet' : 'mainnet'].chainId,
      },
    });
  }

  return WalletClass.create({
    publicKey: Buffer.from(publicKey),
    workchain: WORKCHAIN,
  });
}

export async function getWalletInfo(network: ApiNetwork, walletOrAddress: TonWallet | string): Promise<ApiWalletInfo> {
  const address = typeof walletOrAddress === 'string'
    ? walletOrAddress
    : toBase64Address(walletOrAddress.address, undefined, network);

  return (await getWalletInfos(network, [address]))[address];
}

export async function fetchBalances(network: ApiNetwork, address: string, sendUpdateTokens: NoneToVoidFunction) {
  const [{ balance: tonBalance }, tokenBalances] = await Promise.all([
    getWalletInfo(network, address),
    loadTokenBalances(network, address, sendUpdateTokens),
  ]);

  return {
    [TONCOIN.slug]: tonBalance,
    ...tokenBalances,
  };
}

export async function getContractInfo(network: ApiNetwork, address: string): Promise<{
  isInitialized: boolean;
  isSwapAllowed?: boolean;
  isWallet?: boolean;
  contractInfo?: ContractInfo;
  codeHash?: string;
  codeHashOld?: string;
}> {
  const data = await getTonClient(network).getAddressInfo(address);

  const { code, state } = data;

  const codeHashOld = Buffer.from(await sha256(base64ToBytes(code))).toString('hex');
  // For inactive addresses, `code` is an empty string. Cell.fromBase64 throws when `code` is an empty string.
  const codeHash = code && Cell.fromBase64(code).hash().toString('hex');

  const contractInfo = Object.values(KnownContracts).find(
    (info) => info.hash === codeHash || info.oldHash === codeHashOld,
  );

  const isInitialized = state === 'active';
  const isWallet = state === 'active' ? contractInfo?.type === ContractType.Wallet : undefined;
  const isSwapAllowed = contractInfo?.isSwapAllowed;

  return {
    isInitialized,
    isWallet,
    isSwapAllowed,
    contractInfo,
    codeHash,
    codeHashOld,
  };
}

export async function getWalletBalance(network: ApiNetwork, walletOrAddress: TonWallet | string): Promise<bigint> {
  return (await getWalletInfo(network, walletOrAddress)).balance;
}

export async function getWalletSeqno(network: ApiNetwork, walletOrAddress: TonWallet | string): Promise<number> {
  const { seqno } = await getWalletInfo(network, walletOrAddress);
  return seqno || 0;
}

export async function pickBestWallet(network: ApiNetwork, publicKey: Uint8Array): Promise<{
  wallet: TonWallet;
  version: ApiTonWalletVersion;
  balance: bigint;
  lastTxId?: string;
}> {
  const allWallets = await getWalletVersionInfos(network, publicKey);
  const defaultWallets = allWallets.filter(({ version }) => version === DEFAULT_WALLET_VERSION);
  const defaultWallet = defaultWallets.find(
    ({ isTestnetSubwalletId }) => isTestnetSubwalletId,
  ) ?? defaultWallets[0];

  if (defaultWallet.lastTxId) {
    return defaultWallet;
  }

  const withBiggestBalance = allWallets.reduce<typeof allWallets[0] | undefined>((best, current) => {
    return current.balance > (best?.balance ?? 0n) ? current : best;
  }, undefined);

  if (withBiggestBalance) {
    return withBiggestBalance;
  }

  const withLastTx = findLast(allWallets, ({ lastTxId }) => !!lastTxId);

  if (withLastTx) {
    return withLastTx;
  }

  // Workaround for NOT holders who do not have transactions
  const v4Wallet = allWallets.find(({ version }) => version === 'v4R2')!;
  const { jettonWallets: v4JettonBalances = [] } = await fetchJettonWallets(network, v4Wallet.address, 1);
  if (v4JettonBalances.length > 0) {
    return v4Wallet;
  }

  return defaultWallet;
}

export async function getWalletVersionInfos(
  network: ApiNetwork,
  publicKey: Uint8Array,
  versions: ApiTonWalletVersion[] = ALL_WALLET_VERSIONS,
): Promise<(ApiWalletWithVersionInfo & { wallet: TonWallet })[]> {
  const items = getWalletVersions(network, publicKey, versions);
  const walletInfos = await getWalletInfos(network, extractKey(items, 'address'));

  const result = items.map((item) => {
    const walletInfo = walletInfos[item.address] ?? {
      balance: 0n,
      isInitialized: false,
    };

    return {
      ...walletInfo,
      ...item,
    };
  });

  return result;
}

type ApiTonWalletVersionInfo = {
  wallet: TonWallet;
  address: string;
  version: ApiTonWalletVersion;
  isTestnetSubwalletId?: boolean;
};

export function getWalletVersions(
  network: ApiNetwork,
  publicKey: Uint8Array,
  versions: ApiTonWalletVersion[] = ALL_WALLET_VERSIONS,
): ApiTonWalletVersionInfo[] {
  return versions.flatMap((version): ApiTonWalletVersionInfo | ApiTonWalletVersionInfo[] => {
    if (version === 'W5' && network === 'testnet') {
      // Support wallets with both `subwallet_id` values for testnet to keep backwards compatibility
      const testnetWallet = buildWallet(publicKey, version, true);
      const testnetAddress = toBase64Address(testnetWallet.address, false, 'testnet');

      const mainnetWallet = buildWallet(publicKey, version, false);
      const mainnetAddress = toBase64Address(mainnetWallet.address, false, 'testnet');

      return [{
        wallet: testnetWallet,
        address: testnetAddress,
        version,
        isTestnetSubwalletId: true,
      }, {
        wallet: mainnetWallet,
        address: mainnetAddress,
        version,
        isTestnetSubwalletId: false,
      }];
    }

    const wallet = buildWallet(publicKey, version);
    const address = toBase64Address(wallet.address, false, network);

    return {
      wallet,
      address,
      version,
      isTestnetSubwalletId: undefined,
    };
  });
}

export function getWalletStateInit(storedWallet: ApiTonWallet) {
  const wallet = getTonWallet(storedWallet);

  return beginCell()
    .storeWritable(storeStateInit(wallet.init))
    .endCell();
}

export function pickWalletByAddress(network: ApiNetwork, publicKey: Uint8Array, address: string) {
  address = toBase64Address(address, false, network);

  const allWallets = getWalletVersions(network, publicKey);

  return allWallets.find((w) => w.address === address)!;
}

/**
 * Check if the wallet is with testnet subwallet ID
 * @returns `undefined` if the wallet is not a W5 wallet,
 * `true` if the wallet is with testnet subwallet ID, `false` otherwise
 */
function checkIsTestnetSubwalletId(
  publicKey: Uint8Array,
  version: ApiTonWalletVersion,
  address: string,
): boolean | undefined {
  if (version !== 'W5') {
    return undefined;
  }

  const testnetSubwalletAddress = publicKeyToAddress('testnet', publicKey, version, true);

  return address === testnetSubwalletAddress;
}

export function getTonWallet(tonWallet: ApiTonWallet) {
  const { publicKey, version, address } = tonWallet;
  if (!publicKey) {
    throw new Error('Public key is missing');
  }

  // For W5 wallets, determine the correct subwallet ID by comparing addresses
  if (version === 'W5') {
    const isTestnetSubwalletId = checkIsTestnetSubwalletId(hexToBytes(publicKey), version, address);
    return buildWallet(publicKey, version, isTestnetSubwalletId);
  }

  return buildWallet(publicKey, version);
}

export async function verifyLedgerWalletAddress(accountId: string): Promise<string | { error: ApiAnyDisplayError }> {
  const { network } = parseAccountId(accountId);
  const [wallet, { verifyLedgerTonAddress }] = await Promise.all([
    fetchStoredWallet(accountId, 'ton'),
    import('./ledger'),
  ]);
  return verifyLedgerTonAddress(network, wallet);
}
