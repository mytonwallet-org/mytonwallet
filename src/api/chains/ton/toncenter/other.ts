import type { ApiNetwork, ApiWalletInfo } from '../../../types';
import type { ApiTonWalletVersion } from '../types';
import type { AccountState, AddressBook, MetadataMap, WalletState, WalletVersion } from './types';

import { TONCENTER_ACTIONS_VERSION } from '../../../../config';
import { buildTxId } from '../../../../util/activities';
import { fetchJson } from '../../../../util/fetch';
import { buildCollectionByKey, split } from '../../../../util/iteratees';
import { toRawAddress } from '../util/tonCore';
import { getEnvironment } from '../../../environment';
import { NETWORK_CONFIG } from '../constants';

const ADDRESS_BOOK_CHUNK_SIZE = 128;
const VERSION_MAP: Record<WalletVersion, ApiTonWalletVersion> = {
  'wallet v1 r1': 'simpleR1',
  'wallet v1 r2': 'simpleR2',
  'wallet v1 r3': 'simpleR3',
  'wallet v2 r1': 'v2R1',
  'wallet v2 r2': 'v2R2',
  'wallet v3 r1': 'v3R1',
  'wallet v3 r2': 'v3R2',
  // 'wallet v4 r1': '', // Not used in production, wrapper is missing
  'wallet v4 r2': 'v4R2',
  // 'wallet v5 beta': '', // Not used in production, wrapper is missing
  'wallet v5 r1': 'W5',
};

export async function fetchAddressBook(network: ApiNetwork, addresses: string[]): Promise<AddressBook> {
  const chunks = split(addresses, ADDRESS_BOOK_CHUNK_SIZE);

  const results = await Promise.all(chunks.map((chunk) => {
    return callToncenterV3(network, '/addressBook', {
      address: chunk,
    });
  }));

  return results.reduce((acc, value) => {
    return Object.assign(acc, value);
  }, {} as AddressBook);
}

export async function fixAddressFormat(network: ApiNetwork, address: string): Promise<string> {
  const result: { address_book: Record<string, string> } = await callToncenterV3(network, '/addressBook', { address });
  return result.address_book[address];
}

/**
 * The output dictionary is indexed by the input addresses.
 * Every input address is guaranteed to be a key of the dictionary.
 */
export async function getWalletInfos(network: ApiNetwork, addresses: string[]): Promise<Record<string, ApiWalletInfo>> {
  const { wallets: states, address_book: addressBook } = await callToncenterV3<{
    address_book: AddressBook;
    wallets: WalletState[];
  }>(network, '/walletStates', { address: addresses.join(',') });

  const walletInfoByRawAddress = Object.fromEntries(states.map((state) => [
    state.address.toLowerCase(),
    buildWalletInfo(state, addressBook),
  ]));

  return Object.fromEntries(addresses.map((inputAddress) => {
    const rawAddress = toRawAddress(inputAddress).toLowerCase();
    return [
      inputAddress,
      walletInfoByRawAddress[rawAddress] ?? {
        address: inputAddress,
        balance: 0n,
        isInitialized: false,
        seqno: 0,
      } satisfies ApiWalletInfo,
    ];
  }));
}

function buildWalletInfo(state: WalletState, addressBook: AddressBook): ApiWalletInfo {
  return {
    address: addressBook[state.address].user_friendly,
    version: 'wallet_type' in state ? VERSION_MAP[state.wallet_type] : undefined,
    balance: BigInt(state.balance),
    isInitialized: state.status === 'active',
    seqno: 'seqno' in state ? state.seqno : 0,
    lastTxId: state.last_transaction_hash ? buildTxId(state.last_transaction_hash) : undefined,
    domain: addressBook[state.address].domain ?? undefined,
  };
}

export async function getAccountStates(network: ApiNetwork, addresses: string[]) {
  const { accounts: states } = await callToncenterV3<{
    addressBook: AddressBook;
    accounts: AccountState[];
  }>(network, '/accountStates', { address: addresses.join(',') });

  const addressByRaw = Object.fromEntries(addresses.map((address) => [toRawAddress(address), address]));
  for (const state of states) {
    state.address = addressByRaw[state.address.toLowerCase()];
  }
  return buildCollectionByKey(states, 'address');
}

export function fetchMetadata(network: ApiNetwork, addresses: string[]): Promise<MetadataMap> {
  return callToncenterV3<MetadataMap>(network, '/metadata', { address: addresses.join(',') });
}

export function callToncenterV3<T = any>(network: ApiNetwork, path: string, data?: AnyLiteral) {
  const url = `${NETWORK_CONFIG[network].toncenterUrl}/api/v3${path}`;

  return fetchJson(url, data, {
    headers: getToncenterHeaders(network),
  }) as Promise<T>;
}

export function getToncenterHeaders(network: ApiNetwork) {
  const { apiHeaders, byNetwork } = getEnvironment();
  const apiKey = byNetwork[network].toncenterKey;

  return {
    ...apiHeaders,
    ...(apiKey && { 'X-Api-Key': apiKey }),
    'X-Actions-Version': TONCENTER_ACTIONS_VERSION,
  };
}
