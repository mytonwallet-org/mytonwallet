import type { ApiChain, ApiNetwork, ApiToken } from '../api/types';

import { DEFAULT_CEX_SWAP_SECOND_TOKEN_SLUG, DEFAULT_TRX_SWAP_FIRST_TOKEN_SLUG, TONCOIN, TRX } from '../config';
import formatTonTransferUrl from './ton/formatTransferUrl';

/**
 * Describes the chain features that distinguish it from other chains in the multichain-polymorphic parts of the code.
 */
export interface ChainConfig {
  /** The blockchain title to show in the UI */
  title: string;
  /** Whether the chain supports domain names that resolve to regular addresses */
  isDnsSupported: boolean;
  /** Whether MyTonWallet supports purchasing crypto in that blockchain with a bank card in Russia */
  canBuyWithCardInRussia: boolean;
  /** Whether the chain supports sending asset transfers with a comment */
  isTransferCommentSupported: boolean;
  /** Whether Ledger support is implemented for this chain */
  isLedgerSupported: boolean;
  /** Regular expression for wallet and contract addresses in the chain */
  addressRegex: RegExp;
  /** The same regular expression but matching any prefix of a valid address */
  addressPrefixRegex: RegExp;
  /** The native token of the chain, i.e. the token that pays the fees */
  nativeToken: ApiToken;
  /** Whether our own backend socket (src/api/common/backendSocket.ts) supports this chain */
  doesBackendSocketSupport: boolean;
  /** A swap configuration used to buy the native token in this chain */
  buySwap: {
    tokenInSlug: string;
    amountIn: bigint;
  };
  /**
   * Configuration of the explorer of the chain.
   * The configuration does not contain data for NFT addresses, they must be configured separately.
   */
  explorer: {
    name: string;
    baseUrl: Record<ApiNetwork, string>;
    /** Use `{base}` as the base URL placeholder and `{address}` as the wallet address placeholder */
    address: string;
    /** Use `{base}` as the base URL placeholder and `{address}` as the token address placeholder */
    token: string;
    /** Use `{base}` as the base URL placeholder and `{hash}` as the transaction hash placeholder */
    transaction: string;
    doConvertHashFromBase64: boolean;
  };
  /** Builds a link to transfer assets in this chain. If not set, the chain won't have the Deposit Link modal. */
  formatTransferUrl?(address: string, amount?: bigint, text?: string, jettonAddress?: string): string;
}

const CHAIN_CONFIG: Record<ApiChain, ChainConfig> = {
  ton: {
    title: 'TON',
    isDnsSupported: true,
    canBuyWithCardInRussia: true,
    isTransferCommentSupported: true,
    isLedgerSupported: true,
    addressRegex: /^([-\w_]{48}|0:[\da-h]{64})$/i,
    addressPrefixRegex: /^([-\w_]{1,48}|0:[\da-h]{0,64})$/i,
    nativeToken: TONCOIN,
    doesBackendSocketSupport: true,
    buySwap: {
      tokenInSlug: DEFAULT_CEX_SWAP_SECOND_TOKEN_SLUG,
      amountIn: 100n,
    },
    explorer: {
      name: 'Tonscan',
      baseUrl: {
        mainnet: 'https://tonscan.org/',
        testnet: 'https://testnet.tonscan.org/',
      },
      address: '{base}address/{address}',
      token: '{base}jetton/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: true,
    },
    formatTransferUrl: formatTonTransferUrl,
  },
  tron: {
    title: 'TRON',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isTransferCommentSupported: false,
    isLedgerSupported: false,
    addressRegex: /^T[1-9A-HJ-NP-Za-km-z]{33}$/,
    addressPrefixRegex: /^T[1-9A-HJ-NP-Za-km-z]{0,33}$/,
    nativeToken: TRX,
    doesBackendSocketSupport: true,
    buySwap: {
      tokenInSlug: DEFAULT_TRX_SWAP_FIRST_TOKEN_SLUG,
      amountIn: 10n,
    },
    explorer: {
      name: 'Tronscan',
      baseUrl: {
        mainnet: 'https://tronscan.org/#/',
        testnet: 'https://shasta.tronscan.org/#/',
      },
      address: '{base}address/{address}',
      token: '{base}token20/{address}',
      transaction: '{base}transaction/{hash}',
      doConvertHashFromBase64: false,
    },
  },
};

export function getChainConfig(chain: ApiChain): ChainConfig {
  return CHAIN_CONFIG[chain];
}

export function findChainConfig(chain: string | undefined): ChainConfig | undefined {
  return chain ? CHAIN_CONFIG[chain as ApiChain] : undefined;
}

export function getChainTitle(chain: ApiChain) {
  return getChainConfig(chain).title;
}

export function getIsSupportedChain(chain?: string): chain is ApiChain {
  return !!findChainConfig(chain);
}

export function getSupportedChains() {
  return Object.keys(CHAIN_CONFIG) as (keyof typeof CHAIN_CONFIG)[];
}

export function getChainsSupportingLedger(): ApiChain[] {
  return (Object.keys(CHAIN_CONFIG) as (keyof typeof CHAIN_CONFIG)[])
    .filter((chain) => CHAIN_CONFIG[chain].isLedgerSupported);
}
