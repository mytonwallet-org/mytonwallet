import { Address, beginCell, external, internal, storeMessage } from '@ton/core';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { ApiMfa, ApiNetwork } from '../../types';
import type { EmulationResponse } from './toncenter/emulation';
import type { PreparedTransactionToSign } from './types';
import type { TonWallet } from './util/tonCore';

import { createMfaForwardMessage } from './util/signer';
import { getTonClient } from './util/tonCore';
import { prepareMessage } from './contracts/MfaExtension';
import { resolveMfaExtensionAddress } from './contracts/util';
import { fetchEmulateTrace } from './toncenter/emulation';
import { calculateOutgoingTransactionFee } from './toncenter/transactions';

const MULTIPLIER_NUMERATOR = 3n;
const MULTIPLIER_DENOMINATOR = 2n;
const LOW_BALANCE_TOP_UP = 100_000_000n;
const ZERO_SIGNATURE = Buffer.alloc(64);

export type PreparedMfaRefillBundle = {
  transactions: PreparedTransactionToSign[];
  refills: bigint[];
  /** Linked protected W5 transaction fees from the exact unsigned trace, before the normal safety factor. */
  finalNetworkFees: bigint[];
};

function getRefill(debit: bigint) {
  return (debit * MULTIPLIER_NUMERATOR + MULTIPLIER_DENOMINATOR - 1n) / MULTIPLIER_DENOMINATOR;
}

function isBetween(message: { source: string | null; destination: string | null }, from: Address, to: Address) {
  try {
    return Boolean(message.source && message.destination
      && Address.parse(message.source).equals(from) && Address.parse(message.destination).equals(to));
  } catch {
    return false;
  }
}

function hashesMatch(first: { hash: string; hash_norm?: string }, second: { hash: string; hash_norm?: string }) {
  const firstHashes = [first.hash, first.hash_norm].filter(Boolean);
  const secondHashes = [second.hash, second.hash_norm].filter(Boolean);
  return firstHashes.some((hash) => secondHashes.includes(hash));
}

async function traceDebit(
  network: ApiNetwork,
  extension: Address,
  wallet: WalletContractV5R1,
  transaction: PreparedTransactionToSign,
  fee: bigint,
  extensionSeqno: number,
  expectedBalance: bigint,
): Promise<{ debit: bigint; networkFee: bigint; trace: EmulationResponse } | undefined> {
  const { payload } = createMfaForwardMessage(transaction, wallet, fee, extensionSeqno);
  const authDate = String(Math.floor(Date.now() / 1000));
  const body = prepareMessage(payload, ZERO_SIGNATURE, ZERO_SIGNATURE, authDate);
  const boc = beginCell().store(storeMessage(external({ to: extension, body })))
    .endCell().toBoc().toString('base64');
  const trace = await fetchEmulateTrace(network, boc);
  const extensionTxs = Object.values(trace.transactions).filter((tx) => (
    tx.account.toLowerCase() === extension.toRawString().toLowerCase() && !tx.in_msg.source
  ));
  if (extensionTxs.length !== 1) return undefined;
  const extensionTx = extensionTxs[0];
  const before = BigInt(extensionTx.account_state_before.balance);
  const after = BigInt(extensionTx.account_state_after.balance);
  const forwarded = extensionTx.out_msgs.filter((msg) => isBetween(msg, extension, wallet.address));
  const walletTxs = Object.values(trace.transactions).filter((tx) => (
    tx.account.toLowerCase() === wallet.address.toRawString().toLowerCase()
    && isBetween(tx.in_msg, extension, wallet.address)
    && forwarded.some((msg) => hashesMatch(msg, tx.in_msg))
  ));
  if (forwarded.length !== 1 || walletTxs.length !== 1 || before !== expectedBalance || after > before) {
    return undefined;
  }
  const isSuccessful = (tx: typeof extensionTx) => tx.description.compute_ph.success
    && tx.description.compute_ph.exit_code === 0 && tx.description.action.success
    && tx.description.action.skipped_actions === 0;
  if (!isSuccessful(extensionTx) || !isSuccessful(walletTxs[0])) return undefined;

  return {
    trace,
    debit: before - after,
    // The wallet pays only its own W5 transaction fee. Extension execution is represented by `debit`; recipient and
    // refill-arrival processing are not wallet fees and must not be folded into the displayed/affordability fee.
    networkFee: calculateOutgoingTransactionFee(walletTxs[0]),
  };
}

/**
 * Produces final W5 actions using unsigned, zero-signature trace emulation only. The real MFA request is signed once
 * by the caller after this function returns.
 */
export async function prepareMfaRefillBundle(
  network: ApiNetwork,
  wallet: TonWallet,
  mfa: ApiMfa | undefined,
  transactions: PreparedTransactionToSign[],
  fees: bigint[],
  extensionSeqno: number,
  onRawTrace?: (trace: EmulationResponse) => void,
  quotedRefill?: bigint,
): Promise<PreparedMfaRefillBundle | undefined> {
  if (!(wallet instanceof WalletContractV5R1) || !mfa || transactions.length !== fees.length) return undefined;
  const extensionAddress = await resolveMfaExtensionAddress(network, wallet.address);
  if (!extensionAddress || !Address.parse(extensionAddress).equals(Address.parse(mfa.address))) return undefined;
  const extension = Address.parse(extensionAddress);
  const { balance } = await getTonClient(network).getAddressInfo(extensionAddress);
  const expectedBalance = BigInt(balance);
  const reserveTopUp = expectedBalance <= LOW_BALANCE_TOP_UP ? LOW_BALANCE_TOP_UP : 0n;
  const finalTransactions: PreparedTransactionToSign[] = [];
  const refills: bigint[] = [];
  const finalNetworkFees: bigint[] = [];

  for (let index = 0; index < transactions.length; index++) {
    const original = transactions[index];
    let refill = quotedRefill;
    if (refill === undefined) {
      const originalTrace = await traceDebit(
        network, extension, wallet, original, fees[index], extensionSeqno + index, expectedBalance,
      );
      if (!originalTrace) return undefined;
      refill = getRefill(originalTrace.debit) + reserveTopUp;
    }
    const final = { ...original, messages: [...original.messages, internal({ to: extension, value: refill })] };
    const finalTrace = await traceDebit(
      network, extension, wallet, final, fees[index], extensionSeqno + index, expectedBalance,
    );
    if (!finalTrace || refill < finalTrace.debit) return undefined;
    finalTransactions.push(final);
    refills.push(refill);
    finalNetworkFees.push(finalTrace.networkFee);
    onRawTrace?.(finalTrace.trace);
  }

  return { transactions: finalTransactions, refills, finalNetworkFees };
}
