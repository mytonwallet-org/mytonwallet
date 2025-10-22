import { Address } from '@ton/core';
import { JettonMaster, TonClient } from '@ton/ton';

import { safeExecAsync } from '../../util/safeExec';
import { pause } from '../../util/schedulers';
import { buildTokenTransferBody, commentToBytes, packBytesAsSnakeCell } from './tonCore';

// Remote API token interface
interface RemoteToken {
  chain: 'ton' | 'tron';
  name: string;
  symbol: string;
  slug: string;
  tokenAddress: string;
  decimals: number;
  keywords?: string[];
}

const TONCENTER_RETRY_TIMEOUT = 2000;

let tokensPromise: Promise<RemoteToken[]> | undefined;

export function fetchKnownTokens(): Promise<RemoteToken[]> {
  if (!tokensPromise) {
    tokensPromise = fetchTokensFromApi();
  }
  return tokensPromise;
}

async function fetchTokensFromApi(): Promise<RemoteToken[]> {
  try {
    const response = await fetch('https://api.mytonwallet.org/assets');
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const tokens: RemoteToken[] = await response.json();

    return tokens.filter((token) => token.chain === 'ton');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('Failed to fetch tokens from main API, trying fallback:', error);

    // Try fallback endpoint
    try {
      const fallbackResponse = await fetch('/token-info-cache.json');
      if (!fallbackResponse.ok) {
        throw new Error(`Fallback HTTP error! status: ${fallbackResponse.status}`);
      }
      const fallbackTokens: RemoteToken[] = await fallbackResponse.json();

      return fallbackTokens.filter((token) => token.chain === 'ton');
    } catch (fallbackError) {
      // eslint-disable-next-line no-console
      console.error('Failed to fetch tokens from fallback API:', fallbackError);

      return [];
    }
  }
}

export async function findTokenInfo(identifier: string): Promise<RemoteToken | undefined> {
  try {
    const tokens = await fetchKnownTokens();
    const identifierLower = identifier.toLowerCase();

    // First, try to find by name, symbol, or keywords (case-insensitive)
    const matchingTokens = tokens.filter((token) => token.name.toLowerCase() === identifierLower
      || token.symbol.toLowerCase() === identifierLower
      || (token.keywords && token.keywords.some((keyword) => keyword.toLowerCase() === identifierLower)));

    if (matchingTokens.length === 1) {
      return matchingTokens[0];
    } else if (matchingTokens.length > 1) {
      throw new Error(
        // eslint-disable-next-line @stylistic/max-len
        `Ambiguous token identifier "${identifier}". Multiple tokens found: ${matchingTokens.map((t) => `${t.name} (${t.symbol})`)
          .join(', ')}. Please be more specific.`,
      );
    }

    // If not found by name/symbol/keywords, try to parse as minter address
    try {
      const normalizedAddress = Address.parse(identifier).toString();
      const tokenByAddress = tokens.find((token) => token.tokenAddress === normalizedAddress);

      if (tokenByAddress) {
        return tokenByAddress;
      }
    } catch (err) {
      // Not a valid address, continue
    }

    // Token not found
    return undefined;
  } catch (error) {
    // Re-throw validation errors (like ambiguity)
    if (error instanceof Error && error.message.includes('Ambiguous token identifier')) {
      throw error;
    }

    // For other errors, log and return undefined
    // eslint-disable-next-line no-console
    console.error('Error in findTokenInfo:', error);
    return undefined;
  }
}

const client = new TonClient({
  endpoint: 'https://toncenter.com/api/v2/jsonRPC',
});

const jettonWalletAddressCache: Record<string, Address> = {};

export async function getJettonWalletAddress(
  ownerAddress: string,
  jettonMasterAddress: string,
): Promise<Address> {
  const cacheKey = `${ownerAddress}_${jettonMasterAddress}`;

  if (jettonWalletAddressCache[cacheKey]) {
    return jettonWalletAddressCache[cacheKey];
  }

  try {
    const owner = Address.parse(ownerAddress);
    const master = Address.parse(jettonMasterAddress);
    const jettonMaster = client.open(JettonMaster.create(master));

    let walletAddress = await safeExecAsync(() => jettonMaster.getWalletAddress(owner), {
      shouldIgnoreError: true,
    });

    if (!walletAddress) {
      await pause(TONCENTER_RETRY_TIMEOUT);
      walletAddress = await jettonMaster.getWalletAddress(owner);
    }

    jettonWalletAddressCache[cacheKey] = walletAddress;

    return walletAddress;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error getting jetton wallet address:', error);
    throw new Error('Failed to get jetton wallet address');
  }
}

export function createJettonTransferPayload(
  fromAddress: string,
  toAddress: string,
  amount: bigint,
  comment?: string,
): string {
  try {
    const body = buildTokenTransferBody({
      tokenAmount: amount,
      toAddress,
      responseAddress: fromAddress,
      forwardPayload: comment ? packBytesAsSnakeCell(commentToBytes(comment)) : undefined,
    });

    return body.toBoc().toString('base64');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error creating jetton transfer payload:', error);
    throw new Error('Failed to create jetton transfer payload');
  }
}
