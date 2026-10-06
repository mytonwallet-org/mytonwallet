import type { ZerionApplicationMetadata, ZerionFungibleInfo, ZerionTransaction } from '../types';

import { normalizeAddress } from '../address';
import { getZerionFungibleImplementation } from './tokens';

export type ZerionApproval = {
  tokenAddress: string;
  fungibleInfo: ZerionFungibleInfo;
  spenderAddress: string;
  spenderName?: string;
  spenderIcon?: string;
  /**
   * The allowance the transaction sets, in base units, and `0n` when the approval is revoked.
   * `undefined` when the reported quantity is not an integer: the pair is still a candidate whose
   * live allowance can be read on-chain, but nothing can be said about what this transaction set.
   */
  amount: bigint | undefined;
};

function findZerionAct(tx: ZerionTransaction, actId: string) {
  return tx.attributes.acts?.find((act) => act.id === actId);
}

export function resolveZerionActMetadata(
  tx: ZerionTransaction,
  actId: string,
): ZerionApplicationMetadata | undefined {
  return findZerionAct(tx, actId)?.application_metadata ?? tx.attributes.application_metadata;
}

/**
 * The fungible allowances a transaction sets, both grants and revokes. NFT and collection approvals
 * are left out: they carry no fungible token to attribute the allowance to.
 *
 * The spender is taken from the act the approval belongs to, and from `approvals[].sender` when the
 * act carries no contract. Transaction-level metadata is not used for it, because it names the dapp
 * that was called rather than the contract that receives the allowance.
 */
export function collectZerionApprovals(tx: ZerionTransaction, zerionChain: string): ZerionApproval[] {
  const approvals: ZerionApproval[] = [];

  for (const approval of tx.attributes.approvals) {
    if (!approval.fungible_info) continue;

    const implementation = getZerionFungibleImplementation(approval.fungible_info, zerionChain);

    if (!implementation?.address) continue;

    const act = findZerionAct(tx, approval.act_id);
    const spenderAddress = act?.application_metadata?.contract_address ?? approval.sender;

    if (!spenderAddress) continue;

    const metadata = act?.application_metadata ?? tx.attributes.application_metadata;

    approvals.push({
      tokenAddress: normalizeAddress(implementation.address),
      fungibleInfo: approval.fungible_info,
      spenderAddress: normalizeAddress(spenderAddress),
      spenderName: metadata?.name,
      spenderIcon: metadata?.icon?.url,
      amount: parseAllowanceAmount(approval.quantity.int),
    });
  }

  return approvals;
}

function parseAllowanceAmount(quantity: string): bigint | undefined {
  try {
    return BigInt(quantity);
  } catch {
    return undefined;
  }
}
