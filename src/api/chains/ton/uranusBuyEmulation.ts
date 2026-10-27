import { Cell } from '@ton/core';

import type { EmulationResponse } from './toncenter/emulation';
import type { TraceDetail, Transaction } from './toncenter/types';

import { areAddressesEqual } from './util/tonCore';

const INTERNAL_TRANSFER_OPCODE = 0x178d4519;
// One percentage point allows a modest favorable price move between estimate and emulation.
const PRICE_DRIFT_BPS = 100;

export class UranusPriceDriftError extends Error {
  constructor() {
    super('Uranus memepad emulation: signed minimum is below independent price bound');
  }
}

function requireCondition(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`Uranus memepad buy emulation: ${message}`);
}

function isSuccessful(transaction: Transaction) {
  const { description } = transaction;
  return description.type === 'ord'
    && !description.aborted
    && !transaction.in_msg.bounced
    && description.compute_ph?.success === true
    && description.action?.success === true;
}

function collectTraceTransactions(trace: EmulationResponse): Transaction[] {
  const transactions: Transaction[] = [];
  const visit = (node: TraceDetail) => {
    const transaction = trace.transactions[node.tx_hash];
    requireCondition(!!transaction, 'trace transaction is missing');
    transactions.push(transaction);
    node.children.forEach(visit);
  };
  visit(trace.trace);
  return transactions;
}

/** Verifies the mint caused by the exact signed buy against the on-chain emulation. */
export function validateUranusBuyEmulation(options: {
  trace: EmulationResponse;
  signerAddress: string;
  masterAddress: string;
  ownerJettonWallet: string;
  buyPayload: Cell;
  minimalAmountOut: bigint;
  slippage: number;
}) {
  const {
    trace, signerAddress, masterAddress, ownerJettonWallet,
    buyPayload, minimalAmountOut, slippage,
  } = options;
  const transactions = collectTraceTransactions(trace);
  const masterTransactions = transactions.filter((tx) => areAddressesEqual(tx.account, masterAddress)
    && tx.in_msg.source && areAddressesEqual(tx.in_msg.source, signerAddress)
    && tx.in_msg.destination && areAddressesEqual(tx.in_msg.destination, masterAddress));
  requireCondition(masterTransactions.length === 1, 'exactly one direct master transaction is required');
  const masterTx = masterTransactions[0];
  requireCondition(isSuccessful(masterTx), 'master transaction failed or bounced');

  const walletTx = transactions.find((tx) => areAddressesEqual(tx.account, signerAddress)
    && tx.out_msgs.some((message) => message.hash === masterTx.in_msg.hash));
  requireCondition(!!walletTx && isSuccessful(walletTx), 'signed wallet transaction is missing or failed');
  const buyBody = masterTx.in_msg.message_content?.body;
  requireCondition(!!buyBody, 'master input body is missing');
  let parsedBuyBody: Cell;
  try {
    parsedBuyBody = Cell.fromBase64(buyBody);
  } catch {
    throw new Error('Uranus memepad buy emulation: master input body is invalid');
  }
  requireCondition(parsedBuyBody.hash().equals(buyPayload.hash()), 'master input differs from the signed buy');

  const mintMessages = masterTx.out_msgs.filter((message) => message.opcode === '0x178d4519');
  requireCondition(mintMessages.length === 1, 'exactly one mint message is required');
  const mint = mintMessages[0];
  requireCondition(!!mint.source && areAddressesEqual(mint.source, masterAddress)
    && !!mint.destination && areAddressesEqual(mint.destination, ownerJettonWallet)
    && !mint.bounced, 'mint does not target the signer jetton wallet');
  const receivingWalletTx = transactions.find((tx) => areAddressesEqual(tx.account, ownerJettonWallet)
    && tx.in_msg.hash === mint.hash);
  requireCondition(!!receivingWalletTx && isSuccessful(receivingWalletTx), 'jetton wallet did not accept the mint');

  let emulatedOut: bigint;
  try {
    const slice = Cell.fromBase64(mint.message_content.body).beginParse();
    requireCondition(slice.loadUint(32) === INTERNAL_TRANSFER_OPCODE, 'mint opcode is invalid');
    slice.loadUintBig(64); // query_id
    emulatedOut = slice.loadCoins();
  } catch {
    throw new Error('Uranus memepad buy emulation: mint body is invalid');
  }
  requireCondition(emulatedOut > 0n, 'mint output must be positive');

  const slippageBps = Math.round(slippage * 100);
  requireCondition(Number.isInteger(slippageBps) && slippageBps >= 0
    && slippageBps + PRICE_DRIFT_BPS < 10_000, 'slippage is invalid');
  const minimumFromEmulation = emulatedOut * BigInt(10_000 - slippageBps - PRICE_DRIFT_BPS) / 10_000n;
  if (minimalAmountOut < minimumFromEmulation) throw new UranusPriceDriftError();
  return emulatedOut;
}
