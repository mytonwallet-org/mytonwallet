import type { Cell, Slice } from '@ton/core';
import { Address } from '@ton/core';

import type { ApiDedustNativeSwapPayload, ApiNetwork } from '../../../types';

import { TONCOIN } from '../../../../config';
import { buildTokenSlug, getTokenByAddress } from '../../../common/tokens';
import { fetchToken } from '../tokens';
import { getContractInfo } from '../wallet';
import { areAddressesEqual, getTonClient, toBase64Address } from './tonCore';

const NATIVE_VAULT = 'EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_';
const FACTORY = 'EQBfBWT7X2BHg9tXAxzhz2aKiNTU1tpt5NsiK0uSDW_YAJ67';
// The deployed volatile pool used by TON/DUST. Factory derivation also verifies its identity and assets.
const POOL_CODE_HASH = '1275095b6da3911292406f4f4386f9e780099b854c6dee9ee2895ddce70927c1';
const MAX_GAS = 300_000_000n;

/** https://docs.dedust.io/reference/tlb-schemes — Native Vault swap, SwapStep and SwapParams. */
export async function parseDedustNativeSwapPayload(
  network: ApiNetwork,
  address: string,
  slice: Slice,
  queryId: bigint,
  options?: { expectedOwnerAddress?: string; messageAmount?: bigint; stateInit?: string },
): Promise<ApiDedustNativeSwapPayload | undefined> {
  const { expectedOwnerAddress, messageAmount, stateInit } = options ?? {};
  if (network !== 'mainnet' || !expectedOwnerAddress || messageAmount === undefined || stateInit
    || !areAddressesEqual(address, NATIVE_VAULT)) return undefined;

  const amount = slice.loadCoins();
  const poolAddress = slice.loadAddress();
  const kind = slice.loadBit();
  const minimumAmountOut = slice.loadCoins();
  const next = slice.loadMaybeRef();
  const params = slice.loadRef().beginParse();
  slice.endParse();
  const deadline = params.loadUint(32);
  const recipient = params.loadMaybeAddress();
  const referral = params.loadMaybeAddress();
  const fulfillPayload = params.loadMaybeRef();
  const rejectPayload = params.loadMaybeRef();
  params.endParse();

  // Unsupported routes and arbitrary callbacks remain unknown, even if their emulation looks like a swap.
  if (amount <= 0n || messageAmount <= amount || messageAmount - amount > MAX_GAS
    || kind || next || minimumAmountOut <= 0n || referral
    || (recipient && !areAddressesEqual(recipient, expectedOwnerAddress))
    || !isSupportedNotification(fulfillPayload) || !isSupportedNotification(rejectPayload)) return undefined;

  const [vault, pool, owner] = await Promise.all([
    getContractInfo(network, address),
    getContractInfo(network, poolAddress.toString()),
    fulfillPayload || rejectPayload ? getContractInfo(network, expectedOwnerAddress) : undefined,
  ]);
  if (!vault.isInitialized || vault.contractInfo?.name !== 'dedustVaultNativeV2'
    || !pool.isInitialized || pool.codeHash !== POOL_CODE_HASH) return undefined;
  // The 32-bit DeDust notification is inert in these standard wallets. Do not assume that for custom wallets.
  if (owner && (!owner.isInitialized || !['v3R2', 'v4R2', 'W5'].includes(owner.contractInfo?.name ?? ''))) {
    return undefined;
  }

  const client = getTonClient(network);
  const [{ stack: assets }, { stack: poolType }] = await Promise.all([
    client.runMethod(poolAddress, 'get_assets'),
    client.runMethod(poolAddress, 'is_stable'),
  ]);
  const assetCells = [assets.readCell(), assets.readCell()];
  if (assets.remaining || poolType.readBigNumber() !== 0n || poolType.remaining) return undefined;
  const parsedAssets = assetCells.map((cell) => readAsset(network, cell.beginParse()));
  const outputAsset = parsedAssets[1];
  if (parsedAssets[0]?.slug !== TONCOIN.slug || !outputAsset?.tokenAddress) return undefined;

  const { stack } = await client.runMethod(Address.parse(FACTORY), 'get_pool_address', [
    { type: 'int', value: 0n },
    ...assetCells.map((cell) => ({ type: 'slice' as const, cell })),
  ]);
  if (!stack.readAddress().equals(poolAddress) || stack.remaining) return undefined;

  const toToken = getTokenByAddress(outputAsset.tokenAddress, 'ton')
    ?? await fetchToken(network, outputAsset.tokenAddress);
  if ('error' in toToken || !Number.isInteger(toToken.decimals) || toToken.decimals < 0 || toToken.decimals > 255) {
    return undefined;
  }

  return {
    type: 'dedust:native-swap', queryId, amount,
    poolAddress: toBase64Address(poolAddress, true, network),
    toSlug: outputAsset.slug, toToken: { ...toToken, slug: outputAsset.slug }, minimumAmountOut,
    recipientAddress: toBase64Address(expectedOwnerAddress, undefined, network), deadline,
  };
}

function isSupportedNotification(cell: Cell | null) {
  if (!cell) return true;
  const slice = cell.beginParse();
  // Exact notification emitted by dedust.io; no arguments, references or nested instructions.
  return slice.remainingBits === 32 && !slice.remainingRefs && slice.loadUint(32) === 0x2e1cfa82;
}

function readAsset(network: ApiNetwork, slice: Slice) {
  const type = slice.loadUint(4);
  let slug: string;
  let tokenAddress: string | undefined;
  if (type === 0) {
    slug = TONCOIN.slug;
  } else if (type === 1) {
    const address = new Address(slice.loadInt(8), slice.loadBuffer(32));
    tokenAddress = toBase64Address(address, true, network);
    slug = buildTokenSlug('ton', tokenAddress);
  } else {
    return undefined;
  }
  slice.endParse();
  return { slug, tokenAddress };
}
