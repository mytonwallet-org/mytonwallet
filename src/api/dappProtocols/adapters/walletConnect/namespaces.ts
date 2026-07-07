import type { WalletKitTypes } from '@reown/walletkit';
import type { AuthTypes, ProposalTypes, Verify } from '@walletconnect/types';

import type { ApiNetwork, EVMChain } from '../../../types';
import type { StoredSessionChain } from '../../storage';
import type { DappConnectionRequest } from '../../types';
import type { DappProtocolType } from '../../types';
import type { ChainId, WalletConnectNamespaces, WalletConnectSessionProposal } from './types';
import { CHAIN_IDS, CHAIN_IDS_BY_CHAIN, EVM_CHAIN_IDS } from './types';

import { fetchStoredChainAccount } from '../../../common/accounts';

const WALLET_CONNECT_EVM_AUTH_METHODS = [
  'personal_sign',
  'eth_sign',
  'eth_signTypedData',
  'eth_signTypedData_v4',
  'eth_sendTransaction',
  'eth_signTransaction',
  'wallet_getCapabilities',
] as const;

const WALLET_CONNECT_SOLANA_AUTH_METHODS = [
  'solana_signMessage',
  'solana_signTransaction',
  'solana_signAllTransactions',
] as const;

export const WALLET_CONNECT_SUPPORTED_AUTH_METHODS = [
  ...WALLET_CONNECT_EVM_AUTH_METHODS,
  ...WALLET_CONNECT_SOLANA_AUTH_METHODS,
];

/** Reverse lookup: (EVM chain, network) → CAIP-2 `eip155:*` id used in WalletConnect. */
export function getEip155Caip2ForEvmChain(chain: EVMChain, network: ApiNetwork): string | undefined {
  for (const [caip2, entry] of Object.entries(EVM_CHAIN_IDS)) {
    if (entry.chain === chain && entry.network === network) {
      return caip2;
    }
  }
  return undefined;
}

/**
 * Extract session chains from WalletConnect namespaces.
 */
export function namespacesToSessionChains(
  namespaces: WalletConnectNamespaces,
) {
  const chains: ChainId[] = [];

  for (const [ns, config] of Object.entries(namespaces)) {
    const chainVariants = CHAIN_IDS_BY_CHAIN[ns];

    for (const chain of config?.chains || []) {
      if (chainVariants[chain]) {
        chains.push({
          chain: chainVariants[chain].chain,
          network: chainVariants[chain].network,
        });
      }
    }
  }

  return chains;
}

export function authPayloadChainsToSessionChains(chains: string[]): ChainId[] {
  const sessionChains: ChainId[] = [];

  for (const caip2 of chains) {
    const chainId = CHAIN_IDS[caip2];
    if (chainId) {
      sessionChains.push(chainId);
    }
  }

  return sessionChains;
}

export function buildSessionAuthenticateProtocolData(
  payload: WalletKitTypes.SessionAuthenticate,
  populatedAuthPayload: AuthTypes.PayloadParams,
  verifyContext?: Verify.Context,
): WalletConnectSessionProposal {
  const { id, topic, params } = payload;

  return {
    id,
    isSessionAuthenticate: true,
    authenticatePayload: populatedAuthPayload,
    verifyContext,
    params: {
      id,
      pairingTopic: topic,
      expiryTimestamp: params.expiryTimestamp,
      relays: [{ protocol: 'irn' }],
      proposer: params.requester,
      requiredNamespaces: chainsToRequiredNamespaces(populatedAuthPayload.chains),
      optionalNamespaces: {},
    },
  };
}

export function getRequestedChainsForApproval(
  message: DappConnectionRequest<DappProtocolType.WalletConnect>,
  network: ApiNetwork,
): StoredSessionChain[] {
  return message.requestedChains.map((chain) => ({
    ...chain,
    network: message.transport === 'extension' ? network : chain.network,
    address: '',
  }));
}

export async function getAccountChains(
  message: DappConnectionRequest<DappProtocolType.WalletConnect>,
  network: ApiNetwork,
  accountId: string,
  chains: ChainId[],
) {
  return await Promise.all(chains.map(async (e) => ({
    ...e,
    network: message.transport === 'extension' ? network : e.network,
    address: (await fetchStoredChainAccount(accountId, e.chain)).byChain[e.chain].address,
  })));
}

/** EIP-5792 `wallet_getCapabilities`: normalize hex chain id (no leading zero digits after `0x`). */
export function normalizeEip155HexChainId(hex: string): string {
  const withPrefix = hex.startsWith('0x') ? hex : `0x${hex}`;
  return `0x${BigInt(withPrefix).toString(16)}`;
}

export function caip2ToHexChainId(caip2: string): string {
  const match = /^eip155:(\d+)$/.exec(caip2);
  if (!match) {
    throw new Error('Invalid CAIP-2 chain id');
  }
  return `0x${BigInt(match[1]).toString(16)}`;
}

export function hexToEip155Caip2(hex: string): string {
  const withPrefix = hex.startsWith('0x') ? hex : `0x${hex}`;
  return `eip155:${BigInt(withPrefix)}`;
}

function getWalletConnectAuthMethodsForNamespace(namespace: string): string[] {
  if (namespace === 'eip155') {
    return [...WALLET_CONNECT_EVM_AUTH_METHODS];
  }

  if (namespace === 'solana') {
    return [...WALLET_CONNECT_SOLANA_AUTH_METHODS];
  }

  return [];
}

function chainsToRequiredNamespaces(chains: string[]): ProposalTypes.RequiredNamespaces {
  const namespaces: ProposalTypes.RequiredNamespaces = {};

  for (const caip2 of chains) {
    const namespace = caip2.split(':')[0];

    if (!namespaces[namespace]) {
      namespaces[namespace] = {
        chains: [],
        methods: getWalletConnectAuthMethodsForNamespace(namespace),
        events: [],
      };
    }

    const nsChains = namespaces[namespace].chains!;

    if (!nsChains.includes(caip2)) {
      nsChains.push(caip2);
    }
  }

  return namespaces;
}
