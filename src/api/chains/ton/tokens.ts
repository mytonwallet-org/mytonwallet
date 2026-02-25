import { Address, Cell } from '@ton/core';

import type { MetadataMap } from './toncenter/types';
import type { JettonMetadata, TonTransferParams } from './types';
import {
  type ApiBalanceBySlug,
  type ApiNetwork,
  type ApiToken,
  type ApiTokenWithMaybePrice,
  type ApiTokenWithPrice,
} from '../../types';

import { getToncoinAmountForTransfer } from '../../../util/fee/getTonOperationFees';
import { fetchJsonWithProxy, fixIpfsUrl } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import withCacheAsync from '../../../util/withCacheAsync';
import { fetchJettonMetadata, fixBase64ImageData, parsePayloadBase64 } from './util/metadata';
import {
  buildTokenTransferBody,
  getTokenBalance,
  getTonClient,
  resolveTokenAddress,
  resolveTokenWalletAddress,
  toBase64Address, toRawAddress,
} from './util/tonCore';
import { buildTokenSlug, getTokenByAddress, updateTokens } from '../../common/tokens';
import { callToncenterV3 } from './toncenter/other';
import { DEFAULT_DECIMALS, TOKEN_TRANSFER_FORWARD_AMOUNT } from './constants';
import { updateTokenHashes } from './priceless';
import { isActiveSmartContract } from './wallet';

export type TokenBalanceParsed = {
  slug: string;
  balance: bigint;
  token: ApiToken;
  jettonWallet: string;
};

type ToncenterJettonWallet = {
  address: string;
  balance: string;
  jetton: string;
  owner: string;
  last_transaction_lt: string;
};

type JettonWalletsResponse = {
  jetton_wallets: ToncenterJettonWallet[];
  metadata?: MetadataMap;
};

async function getTokenBalances(network: ApiNetwork, address: string) {
  const { jettonWallets, metadata } = await fetchJettonWallets(network, address);
  const parsed = await Promise.all(
    jettonWallets.map((wallet) => parseTokenBalance(network, wallet, metadata)),
  );
  return parsed.filter(Boolean);
}
const JETTON_WALLETS_LIMIT = 1000;

export async function fetchJettonWallets(network: ApiNetwork, address: string, maxLimit?: number) {
  const jettonWallets: ToncenterJettonWallet[] = [];
  let metadata: MetadataMap = {};
  let offset = 0;
  const limit = maxLimit && maxLimit < JETTON_WALLETS_LIMIT ? maxLimit : JETTON_WALLETS_LIMIT;

  while (true) {
    const requestLimit = Math.min(limit, maxLimit ? maxLimit - jettonWallets.length : limit);
    const {
      jetton_wallets: newJettonWallets = [],
      metadata: newMetadata = {},
    } = await callToncenterV3<JettonWalletsResponse>(network, '/jetton/wallets', {
      owner_address: address,
      exclude_zero_balance: false,
      limit: requestLimit,
      offset,
    });
    jettonWallets.push(...newJettonWallets);
    metadata = { ...metadata, ...newMetadata };

    // Check if we have reached the end of the jetton wallets
    if (newJettonWallets.length < requestLimit) {
      break;
    }

    // Check if we fetched enough jetton wallets
    if (maxLimit && jettonWallets.length >= maxLimit) {
      break;
    }

    offset += newJettonWallets.length;
  }

  return { jettonWallets, metadata };
}

async function parseTokenBalance(
  network: ApiNetwork,
  wallet: ToncenterJettonWallet,
  metadata: MetadataMap,
): Promise<TokenBalanceParsed | undefined> {
  try {
    const tokenAddress = toBase64Address(wallet.jetton, true, network);
    const jettonMetadata = getJettonMetadataFromMap(wallet.jetton, metadata)
      ?? await fetchJettonMetadata(network, tokenAddress).catch((error) => {
        logDebugError('fetchJettonMetadata', error);
        return undefined;
      });
    const metadataToUse = jettonMetadata && !('error' in jettonMetadata)
      ? jettonMetadata
      : {
        name: tokenAddress,
        symbol: tokenAddress.slice(0, 4),
        decimals: DEFAULT_DECIMALS,
      } satisfies JettonMetadata;

    const token = buildTokenByMetadata(tokenAddress, metadataToUse);

    return {
      slug: token.slug,
      balance: BigInt(wallet.balance),
      token,
      jettonWallet: toBase64Address(wallet.address, undefined, network),
    };
  } catch (err) {
    logDebugError('parseTokenBalance', err);
    return undefined;
  }
}

function getJettonMetadataFromMap(rawAddress: string, metadata: MetadataMap): JettonMetadata | undefined {
  const tokenMetadata = metadata?.[rawAddress]?.token_info?.find((token) => token.type === 'jetton_masters');

  if (!tokenMetadata) {
    return undefined;
  }

  return {
    name: tokenMetadata.name ?? rawAddress,
    symbol: tokenMetadata.symbol ?? tokenMetadata.name ?? rawAddress,
    description: tokenMetadata.description,
    image: tokenMetadata.image,
    decimals: tokenMetadata.extra?.decimals ?? DEFAULT_DECIMALS,
  };
}

export async function insertMintlessPayload(
  network: ApiNetwork,
  fromAddress: string,
  tokenAddress: string,
  transfer: TonTransferParams,
): Promise<TonTransferParams> {
  const { toAddress, payload } = transfer;

  const token = getTokenByAddress(tokenAddress);
  if (typeof payload !== 'string' || !token?.customPayloadApiUrl) {
    return transfer;
  }

  const parsedPayload = await parsePayloadBase64(network, toAddress, payload);
  if (parsedPayload.type !== 'tokens:transfer') {
    throw new Error('Invalid payload');
  }

  const {
    mintlessTokenBalance,
    isMintlessClaimed,
    stateInit,
    customPayload,
  } = await getMintlessParams({
    network,
    token,
    fromAddress,
    tokenWalletAddress: transfer.toAddress,
  });

  if (!mintlessTokenBalance || isMintlessClaimed) {
    return transfer;
  }

  const newPayload = buildTokenTransferBody({
    toAddress: parsedPayload.destination,
    queryId: parsedPayload.queryId,
    tokenAmount: parsedPayload.amount,
    forwardAmount: parsedPayload.forwardAmount,
    forwardPayload: Cell.fromBase64(parsedPayload.forwardPayload!),
    noInlineForwardPayload: true, // Not sure whether it's necessary; setting true to be on the safe side
    responseAddress: parsedPayload.responseDestination,
    customPayload: Cell.fromBase64(customPayload!),
  });

  return {
    ...transfer,
    stateInit: stateInit ? Cell.fromBase64(stateInit) : undefined,
    payload: newPayload,
  };
}

export async function buildTokenTransfer(options: {
  network: ApiNetwork;
  tokenAddress: string;
  fromAddress: string;
  toAddress: string;
  amount: bigint;
  payload?: Cell;
  shouldSkipMintless?: boolean;
  forwardAmount?: bigint;
  isLedger?: boolean;
}) {
  const {
    network,
    tokenAddress,
    fromAddress,
    toAddress,
    amount,
    shouldSkipMintless,
    forwardAmount = TOKEN_TRANSFER_FORWARD_AMOUNT,
    isLedger,
  } = options;
  let { payload } = options;

  const tokenWalletAddress = await resolveTokenWalletAddress(network, fromAddress, tokenAddress);
  const token = getTokenByAddress(tokenAddress)!;

  const {
    isTokenWalletDeployed = !!(await isActiveSmartContract(network, tokenWalletAddress)),
    isMintlessClaimed,
    mintlessTokenBalance,
    customPayload,
    stateInit,
  } = await getMintlessParams({
    network, fromAddress, token, tokenWalletAddress, shouldSkipMintless,
  });

  if (isTokenWalletDeployed) {
    const realTokenAddress = await resolveTokenAddress(network, tokenWalletAddress);
    if (tokenAddress !== realTokenAddress) {
      throw new Error('Invalid contract');
    }
  }

  // In ledger-app-ton v2.7.0 a queryId not equal to 0 is handled incorrectly.
  const queryId = isLedger ? 0n : undefined;

  payload = buildTokenTransferBody({
    tokenAmount: amount,
    toAddress,
    forwardAmount,
    forwardPayload: payload,
    responseAddress: fromAddress,
    customPayload: customPayload ? Cell.fromBase64(customPayload) : undefined,
    queryId,
  });

  // eslint-disable-next-line prefer-const
  let { amount: toncoinAmount, realAmount } = getToncoinAmountForTransfer(
    token, Boolean(mintlessTokenBalance) && !isMintlessClaimed,
  );

  if (forwardAmount > TOKEN_TRANSFER_FORWARD_AMOUNT) {
    toncoinAmount += forwardAmount;
  }

  return {
    amount: toncoinAmount,
    realAmount,
    toAddress: tokenWalletAddress,
    payload,
    stateInit: stateInit ? Cell.fromBase64(stateInit) : undefined,
    mintlessTokenBalance,
    isTokenWalletDeployed,
  };
}

export async function getTokenBalanceWithMintless(network: ApiNetwork, accountAddress: string, tokenAddress: string) {
  const tokenWalletAddress = await resolveTokenWalletAddress(network, accountAddress, tokenAddress);
  const token = getTokenByAddress(tokenAddress)!;

  const {
    isTokenWalletDeployed = !!(await isActiveSmartContract(network, tokenWalletAddress)),
    mintlessTokenBalance,
  } = await getMintlessParams({
    network, fromAddress: accountAddress, token, tokenWalletAddress,
  });

  return calculateTokenBalanceWithMintless(network, tokenWalletAddress, isTokenWalletDeployed, mintlessTokenBalance);
}

export async function calculateTokenBalanceWithMintless(
  network: ApiNetwork,
  tokenWalletAddress: string,
  isTokenWalletDeployed?: boolean,
  mintlessTokenBalance = 0n,
) {
  let balance = 0n;
  if (isTokenWalletDeployed) {
    balance += await getTokenBalance(network, tokenWalletAddress);
  }
  if (mintlessTokenBalance) {
    balance += mintlessTokenBalance;
  }
  return balance;
}

async function getMintlessParams(options: {
  network: ApiNetwork;
  fromAddress: string;
  token: ApiToken;
  tokenWalletAddress: string;
  shouldSkipMintless?: boolean;
}) {
  const {
    network, fromAddress, token, tokenWalletAddress, shouldSkipMintless,
  } = options;

  const isMintlessToken = !!token.customPayloadApiUrl;
  let isTokenWalletDeployed: boolean | undefined;
  let customPayload: string | undefined;
  let stateInit: string | undefined;

  let isMintlessClaimed: boolean | undefined;
  let mintlessTokenBalance: bigint | undefined;

  if (isMintlessToken && !shouldSkipMintless) {
    isTokenWalletDeployed = !!(await isActiveSmartContract(network, tokenWalletAddress));
    isMintlessClaimed = isTokenWalletDeployed && await checkMintlessTokenWalletIsClaimed(network, tokenWalletAddress);

    if (!isMintlessClaimed) {
      const data = await fetchMintlessTokenWalletData(token.customPayloadApiUrl!, fromAddress);
      const isExpired = data
        ? Date.now() > new Date(Number(data.compressed_info.expired_at) * 1000).getTime()
        : true;

      if (data && !isExpired) {
        customPayload = data.custom_payload;
        mintlessTokenBalance = BigInt(data.compressed_info.amount);

        if (!isTokenWalletDeployed) {
          stateInit = data.state_init;
        }
      }
    }
  }

  return {
    isTokenWalletDeployed,
    isMintlessClaimed,
    mintlessTokenBalance,
    customPayload,
    stateInit,
  };
}

export async function checkMintlessTokenWalletIsClaimed(network: ApiNetwork, tokenWalletAddress: string) {
  const res = await getTonClient(network)
    .runMethod(Address.parse(tokenWalletAddress), 'is_claimed');
  return res.stack.readBoolean();
}

async function fetchMintlessTokenWalletData(customPayloadApiUrl: string, address: string) {
  const rawAddress = toRawAddress(address);

  return (await fetchJsonWithProxy(`${customPayloadApiUrl}/wallet/${rawAddress}`).catch(() => undefined)) as {
    custom_payload: string;
    state_init: string;
    compressed_info: {
      amount: string;
      start_from: string;
      expired_at: string;
    };
  } | undefined;
}

export async function fetchToken(network: ApiNetwork, address: string) {
  const metadata = await fetchJettonMetadata(network, address);
  if ('error' in metadata) return metadata;

  return buildTokenByMetadata(address, metadata);
}

function buildTokenByMetadata(address: string, metadata: JettonMetadata): ApiToken {
  const {
    name,
    symbol,
    image,
    image_data: imageData,
    decimals,
    custom_payload_api_uri: customPayloadApiUrl,
  } = metadata;

  return {
    slug: buildTokenSlug('ton', address),
    name,
    symbol,
    decimals: decimals === undefined ? DEFAULT_DECIMALS : Number(decimals),
    chain: 'ton',
    tokenAddress: address,
    image: (image && fixIpfsUrl(image)) || (imageData && fixBase64ImageData(imageData)) || undefined,
    customPayloadApiUrl,
  };
}

export async function importToken(network: ApiNetwork, address: string, sendUpdateTokens: NoneToVoidFunction) {
  const rawToken = await fetchToken(network, address);
  if ('error' in rawToken) {
    logDebugError(`${address} is not a token address`, rawToken);
    return;
  }

  const token: ApiTokenWithPrice = {
    ...rawToken,
    priceUsd: 0,
    percentChange24h: 0,
  };
  await updateTokens([token], sendUpdateTokens);
  await updateTokenHashes(network, [token.slug], sendUpdateTokens);
}

export async function importUnknownTokens(
  network: ApiNetwork,
  tokenAddresses: string[],
  sendUpdateTokens: NoneToVoidFunction,
) {
  await Promise.all(tokenAddresses.map(
    (tokenAddress) => importUnknownToken(network, tokenAddress, sendUpdateTokens),
  ));
}

// Using `withCacheAsync` mainly to prevent concurrent execution
const importUnknownToken = withCacheAsync(importToken);

export async function loadTokenBalances(
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
): Promise<ApiBalanceBySlug> {
  const tokenBalances = await getTokenBalances(network, address);
  const tokens: ApiTokenWithMaybePrice[] = tokenBalances.map(({ token }) => ({
    ...token,
    priceUsd: undefined,
    percentChange24h: undefined,
  }));
  await updateTokens(tokens, sendUpdateTokens);
  await updateTokenHashes(network, tokens.map((token) => token.slug), sendUpdateTokens);

  return Object.fromEntries(tokenBalances.map(({ slug, balance }) => [slug, balance]));
}
