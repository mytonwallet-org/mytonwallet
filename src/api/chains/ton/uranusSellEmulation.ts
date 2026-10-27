import { Cell } from '@ton/core';

import type { EmulationResponse } from './toncenter/emulation';
import type { TraceDetail, Transaction, TransactionMessage } from './toncenter/types';

import { areAddressesEqual } from './util/tonCore';
import { UranusPriceDriftError } from './uranusBuyEmulation';

const WALLET_TO_MASTER_SELL_OPCODE = 0x646ad424;
const SELL_EVENT_OPCODE = '0x3ab0fccc';
const SELL_PAYOUT_OPCODE = '0x66c8ad72';
const PRICE_DRIFT_BPS = 100;

function requireCondition(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`Uranus memepad sell emulation: ${message}`);
}

function isSuccessful(transaction: Transaction) {
  const { description } = transaction;
  return description.type === 'ord'
    && !description.aborted
    && !transaction.in_msg.bounced
    && description.compute_ph?.success === true
    && description.action?.success === true;
}

function collectTransactions(trace: EmulationResponse) {
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

function readBody(message: TransactionMessage) {
  requireCondition(!!message.message_content?.body, 'message body is missing');
  try {
    return Cell.fromBase64(message.message_content.body);
  } catch {
    throw new Error('Uranus memepad sell emulation: message body is invalid');
  }
}

/** The signed sell must burn the signer's tokens and pay the TON proceeds back to that signer. */
export function validateUranusSellEmulation({
  trace, signerAddress, masterAddress, ownerJettonWallet, sellPayload, minimalAmountOut, slippage,
}: {
  trace: EmulationResponse;
  signerAddress: string;
  masterAddress: string;
  ownerJettonWallet: string;
  sellPayload: Cell;
  minimalAmountOut: bigint;
  slippage: number;
}) {
  const transactions = collectTransactions(trace);
  const walletTransactions = transactions.filter((tx) => areAddressesEqual(tx.account, ownerJettonWallet)
    && !!tx.in_msg.source && areAddressesEqual(tx.in_msg.source, signerAddress)
    && !!tx.in_msg.destination && areAddressesEqual(tx.in_msg.destination, ownerJettonWallet)
    && tx.in_msg.opcode === '0xb7459e2c');
  requireCondition(walletTransactions.length === 1, 'exactly one signed sell wallet transaction is required');
  const walletTx = walletTransactions[0];
  requireCondition(isSuccessful(walletTx), 'sell wallet transaction failed or bounced');
  requireCondition(readBody(walletTx.in_msg).hash().equals(sellPayload.hash()),
    'wallet input differs from the signed sell');
  const signerTx = transactions.find((tx) => areAddressesEqual(tx.account, signerAddress)
    && tx.out_msgs.some((message) => message.hash === walletTx.in_msg.hash));
  requireCondition(!!signerTx && isSuccessful(signerTx), 'signed wallet transaction is missing or failed');

  const signed = sellPayload.beginParse();
  signed.loadUint(32);
  const queryId = signed.loadUintBig(64);
  const soldAmount = signed.loadCoins();
  const signedMinimum = signed.loadCoins();
  requireCondition(signedMinimum === minimalAmountOut, 'signed minimum differs from validated minimum');

  const masterMessages = walletTx.out_msgs.filter((message) => message.opcode === '0x646ad424'
    && !!message.destination && areAddressesEqual(message.destination, masterAddress));
  requireCondition(masterMessages.length === 1, 'exactly one wallet-to-master sell is required');
  const masterMessage = masterMessages[0];
  const masterTransactions = transactions.filter((tx) => areAddressesEqual(tx.account, masterAddress)
    && tx.in_msg.hash === masterMessage.hash);
  requireCondition(masterTransactions.length === 1, 'master transaction is missing');
  const masterTx = masterTransactions[0];
  requireCondition(isSuccessful(masterTx), 'master transaction failed or bounced');

  const masterBody = readBody(masterTx.in_msg).beginParse();
  requireCondition(masterBody.loadUint(32) === WALLET_TO_MASTER_SELL_OPCODE
    && masterBody.loadUintBig(64) === queryId
    && masterBody.loadCoins() === soldAmount
    && masterBody.loadCoins() === minimalAmountOut
    && areAddressesEqual(masterBody.loadAddress(), signerAddress),
  'master input does not match the signed sell');
  const excessesTo = masterBody.loadMaybeAddress();
  requireCondition(!!excessesTo && areAddressesEqual(excessesTo, signerAddress)
    && !masterBody.loadMaybeRef() && !masterBody.loadMaybeRef()
    && masterBody.remainingBits === 0 && masterBody.remainingRefs === 0,
  'master sell changes the receiver or fee configuration');

  const events = masterTx.out_msgs.filter((message) => message.opcode === SELL_EVENT_OPCODE);
  requireCondition(events.length === 1, 'exactly one sell event is required');
  const event = readBody(events[0]).beginParse();
  requireCondition(event.loadUint(32) === 0x3ab0fccc
    && areAddressesEqual(event.loadAddress(), signerAddress)
    && event.loadCoins() === soldAmount,
  'sell event does not match the signer and amount');
  const emulatedOut = event.loadCoins();
  requireCondition(emulatedOut > 0n, 'sell output must be positive');

  const payouts = masterTx.out_msgs.filter((message) => message.opcode === SELL_PAYOUT_OPCODE);
  requireCondition(payouts.length === 1, 'exactly one sell payout is required');
  const payout = payouts[0];
  requireCondition(!!payout.destination && areAddressesEqual(payout.destination, signerAddress)
    && !payout.bounced && BigInt(payout.value ?? '0') === emulatedOut,
  'sell payout does not deliver the quoted TON to the signer');
  const receiverTx = transactions.find((tx) => areAddressesEqual(tx.account, signerAddress)
    && tx.in_msg.hash === payout.hash);
  requireCondition(!!receiverTx && isSuccessful(receiverTx), 'signer did not receive the sell payout');

  const slippageBps = Math.round(slippage * 100);
  requireCondition(Number.isInteger(slippageBps) && slippageBps >= 0
    && slippageBps + PRICE_DRIFT_BPS < 10_000, 'slippage is invalid');
  const minimumFromEmulation = emulatedOut * BigInt(10_000 - slippageBps - PRICE_DRIFT_BPS) / 10_000n;
  if (minimalAmountOut < minimumFromEmulation) throw new UranusPriceDriftError();
  return emulatedOut;
}
