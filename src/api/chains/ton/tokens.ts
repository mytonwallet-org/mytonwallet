import type { JettonBalance } from 'tonapi-sdk-js';
import { Address, Cell } from '@ton/core';

import type { ApiBalanceBySlug, ApiNetwork, ApiToken, ApiTokenWithPrice, OnApiUpdate } from '../../types';
import type { AnyPayload, JettonMetadata, TonTransferParams } from './types';

import { TON_USDT_MAINNET_SLUG, TON_USDT_TESTNET_SLUG } from '../../../config';
import { fetchJsonWithProxy, fixIpfsUrl } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { fetchJettonMetadata, fixBase64ImageData, parsePayloadBase64 } from './util/metadata';
import { fetchJettonBalances } from './util/tonapiio';
import {
  buildTokenTransferBody,
  getTokenBalance,
  getTonClient,
  resolveTokenAddress,
  resolveTokenWalletAddress,
  toBase64Address, toRawAddress,
} from './util/tonCore';
import { buildTokenSlug, getTokenByAddress, updateTokens } from '../../common/tokens';
import {
  CLAIM_MINTLESS_AMOUNT,
  DEFAULT_DECIMALS,
  TINIEST_TOKEN_TRANSFER_REAL_AMOUNT,
  TINY_TOKEN_TRANSFER_AMOUNT,
  TINY_TOKEN_TRANSFER_REAL_AMOUNT,
  TOKEN_TRANSFER_AMOUNT,
  TOKEN_TRANSFER_FORWARD_AMOUNT,
  TOKEN_TRANSFER_REAL_AMOUNT,
} from './constants';
import { updateTokenHashes } from './priceless';
import { isActiveSmartContract } from './wallet';

export type TokenBalanceParsed = {
  slug: string;
  balance: bigint;
  token: ApiToken;
  jettonWallet: string;
};

async function getTokenBalances(network: ApiNetwork, address: string) {
  const balancesRaw = await fetchJettonBalances(network, address);
  return balancesRaw.map((balance) => parseTokenBalance(network, balance)).filter(Boolean);
}

function parseTokenBalance(network: ApiNetwork, balanceRaw: JettonBalance): TokenBalanceParsed | undefined {
  if (!balanceRaw.jetton) {
    return undefined;
  }

  try {
    const { balance, jetton, wallet_address: walletAddress } = balanceRaw;
    const tokenAddress = toBase64Address(jetton.address, true, network);
    const token = buildTokenByMetadata(tokenAddress, jetton);

    return {
      slug: token.slug,
      balance: BigInt(balance),
      token,
      jettonWallet: toBase64Address(walletAddress.address, undefined, network),
    };
  } catch (err) {
    logDebugError('parseTokenBalance', err);
    return undefined;
  }
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
    responseAddress: parsedPayload.responseDestination,
    customPayload: Cell.fromBase64(customPayload!),
  });

  return {
    ...transfer,
    stateInit: stateInit ? Cell.fromBase64(stateInit) : undefined,
    payload: newPayload,
    isBase64Payload: false,
  };
}

export async function buildTokenTransfer(options: {
  network: ApiNetwork;
  tokenAddress: string;
  fromAddress: string;
  toAddress: string;
  amount: bigint;
  payload?: AnyPayload;
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
  const token = getTokenByAddress(tokenAddress);

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
  const token = getTokenByAddress(tokenAddress);

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

/**
 * A pure function guessing the "fee" that needs to be attached to the token transfer.
 * In contrast to the blockchain fee, this fee is a part of the transfer itself.
 *
 * `amount` is what should be attached (acts as a fee for the user);
 * `realAmount` is approximately what will be actually spent (the rest will return in the excess).
 */
export function getToncoinAmountForTransfer(token: ApiToken, willClaimMintless: boolean) {
  let amount = 0n;
  let realAmount = 0n;

  if (token.slug === TON_USDT_MAINNET_SLUG || token.slug === TON_USDT_TESTNET_SLUG) {
    amount += TINY_TOKEN_TRANSFER_AMOUNT;
    realAmount += TINIEST_TOKEN_TRANSFER_REAL_AMOUNT;
  } else if (token.isTiny) {
    amount += TINY_TOKEN_TRANSFER_AMOUNT;
    realAmount += TINY_TOKEN_TRANSFER_REAL_AMOUNT;
  } else {
    amount += TOKEN_TRANSFER_AMOUNT;
    realAmount += TOKEN_TRANSFER_REAL_AMOUNT;
  }

  if (willClaimMintless) {
    amount += CLAIM_MINTLESS_AMOUNT;
    realAmount += CLAIM_MINTLESS_AMOUNT;
  }

  return { amount, realAmount };
}

export async function loadTokenBalances(
  network: ApiNetwork,
  address: string,
  onUpdate: OnApiUpdate,
): Promise<ApiBalanceBySlug> {
  const tokenBalances = await getTokenBalances(network, address);
  const tokens: ApiTokenWithPrice[] = tokenBalances.map(({ token }) => ({
    ...token,
    priceUsd: 0,
    percentChange24h: 0,
  }));
  await updateTokens(tokens, onUpdate);
  await updateTokenHashes(network, tokens.map((token) => token.slug), onUpdate);
  return Object.fromEntries(tokenBalances.map(({ slug, balance }) => [slug, balance]));
}
