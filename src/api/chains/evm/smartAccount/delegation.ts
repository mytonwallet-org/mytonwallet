import type { Wallet } from 'ethers';
import { hashAuthorization, Signature } from 'ethers';

import type { ApiNetwork, EVMChain } from '../../../types';
import type { PimlicoEip7702Auth } from './pimlico';
import type { EvmMetaTransaction } from './types';

import { normalizeAddress } from '../address';
import { getEvmDelegationAddress } from '../approvals';
import { ALCHEMY_7702_DELEGATEE_ADDRESSES } from './constants';

function toHex(value: bigint) {
  return `0x${value.toString(16)}`;
}

function toPimlicoEip7702Auth(
  delegate: string,
  chainId: bigint,
  authorizationNonce: bigint,
  signature: string,
): PimlicoEip7702Auth {
  const { r, s, yParity } = Signature.from(signature);

  return {
    address: delegate,
    chainId: toHex(chainId),
    nonce: toHex(authorizationNonce),
    r,
    s,
    yParity: toHex(BigInt(yParity)),
  };
}

/** ECDSA signature over EIP-7702 `hashAuthorization` (Alchemy authorization items, etc.). */
export function signEip7702AuthorizationSignature(
  wallet: Wallet,
  chainId: bigint,
  authorizationNonce: bigint,
  delegate: string,
): string {
  const digest = hashAuthorization({
    address: delegate,
    nonce: authorizationNonce,
    chainId,
  });

  return Signature.from(wallet.signingKey.sign(digest)).serialized;
}

/** Signed authorization in Pimlico bundler `eip7702Auth` shape. */
export function signEip7702Authorization(
  wallet: Wallet,
  chainId: bigint,
  authorizationNonce: bigint,
  delegate: string,
): PimlicoEip7702Auth {
  const signature = signEip7702AuthorizationSignature(
    wallet,
    chainId,
    authorizationNonce,
    delegate,
  );

  return toPimlicoEip7702Auth(delegate, chainId, authorizationNonce, signature);
}

// Reset foreign delegation before submitting batch user operation if user has one.
export function withForeignDelegationResetCall(
  address: string,
  transactions: EvmMetaTransaction[],
  foreignDelegation?: string,
): EvmMetaTransaction[] {
  if (!foreignDelegation) {
    return transactions;
  }

  return [{
    to: address,
    value: 0n,
    data: '0x',
  }, ...transactions];
}

export function resolveBatchDelegation(activeDelegate: string | undefined): {
  foreignDelegation?: string;
  shouldDelegate: boolean;
} {
  if (!activeDelegate) {
    return { shouldDelegate: true };
  }

  const normalized = normalizeAddress(activeDelegate);
  if (ALCHEMY_7702_DELEGATEE_ADDRESSES.has(normalized.toLowerCase())) {
    return { shouldDelegate: false };
  }

  return { foreignDelegation: normalized, shouldDelegate: true };
}

export async function isAlchemy7702Delegated(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<boolean> {
  const activeDelegate = await getEvmDelegationAddress(chain, network, address);

  if (!activeDelegate) return false;

  return ALCHEMY_7702_DELEGATEE_ADDRESSES.has(normalizeAddress(activeDelegate).toLowerCase());
}

export async function getForeignEvmDelegationAddress(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<string | undefined> {
  const activeDelegate = await getEvmDelegationAddress(chain, network, address);

  return resolveBatchDelegation(activeDelegate).foreignDelegation;
}
