import {
  decompileTransactionMessage,
  getBase64Encoder,
  getCompiledTransactionMessageDecoder,
  getTransactionDecoder,
} from '@solana/kit';

import type { ApiDappTransfer, ApiEmulationResult, ApiNetwork } from '../../types';
import type { SolanaCompiledTransaction, SolanaTransactionEmulationResultRaw } from './types';

import { SOLANA } from '../../../config';
import { getTransferSolInstructionDataDecoder } from '../../../lib/solana-program/system';
import { fetchJson } from '../../../util/fetch';
import { parseTokenOperation } from './util/programParsers';
import { updateActivityMetadata } from '../../common/helpers';
import { NETWORK_CONFIG, SOLANA_PROGRAM_IDS } from './constants';

const SIMPLE_PROGRAMS = new Set([
  ...SOLANA_PROGRAM_IDS.system,
  ...SOLANA_PROGRAM_IDS.memo,
  ...SOLANA_PROGRAM_IDS.computeBudget,
]);

// In Solana we don't have separated transfers and payload-driven operations,
// so show only activity and use transfer only to deliver raw tx
function getFakeTransfer(rawTx: string, isDangerous: boolean): ApiDappTransfer {
  return {
    chain: 'solana',
    toAddress: '',
    amount: 1n,
    rawPayload: rawTx,
    isDangerous,
    normalizedAddress: '',
    displayedToAddress: '',
    networkFee: 0n,
  };
}

const DEFAULT_FEE = 5000n;

export async function parseTransactionForPreview(rawTx: string, address: string, network: ApiNetwork) {
  const txBytes = getBase64Encoder().encode(rawTx);

  const decoder = getTransactionDecoder();
  const decodedTransaction = decoder.decode(txBytes);
  const decompiled = getCompiledTransactionMessageDecoder().decode(decodedTransaction.messageBytes);

  const transfers: ApiDappTransfer[] = [];
  let emulation: ApiEmulationResult | undefined = undefined;

  if (isComplexTransaction(decompiled)) {
    const emulated = await emulateTransaction(rawTx, network);

    const tokenOperation = await parseTokenOperation(network, emulated as any, address, decompiled.staticAccounts);

    if (tokenOperation?.assets) {
      transfers.push(getFakeTransfer(rawTx, false));

      if (tokenOperation.isSwap) {
        const { swap } = tokenOperation;

        emulation = {
          networkFee: BigInt(swap.networkFee),
          received: 0n,
          traceOutputs: [],
          // We need to pass TON-like structure, but it's not actual emulation,
          // so we don't have all the fields, but have essential
          activities: [updateActivityMetadata({
            id: '',
            kind: 'swap',
            fromAddress: address,
            timestamp: 0,
            from: swap.from,
            fromAmount: swap.fromAmount,
            to: swap.to,
            toAmount: swap.toAmount,
            networkFee: swap.networkFee,
            swapFee: '0',
            status: 'completed',
            hashes: [],
          })],
          realFee: BigInt(swap.networkFee),
        };
      } else {
        const { transfer } = tokenOperation;

        emulation = {
          networkFee: BigInt(transfer.fee),
          received: 0n,
          traceOutputs: [],
          // We need to pass TON-like structure, but it's not actual emulation,
          // so we don't have all the fields, but have essential
          activities: [updateActivityMetadata({
            id: '',
            kind: 'transaction',
            timestamp: 0,
            comment: undefined,
            fromAddress: address,
            toAddress: transfer.toAddress,
            amount: transfer.amount,
            slug: transfer.slug,
            isIncoming: false,
            normalizedAddress: transfer.toAddress,
            fee: BigInt(transfer.fee),
            status: 'completed',
          })],
          realFee: BigInt(transfer.fee),
        };
      }
    }
    // fallback to preview w/o detail & w/ warning
    if (!transfers.length) {
      transfers.push(getFakeTransfer(rawTx, true));
    }
    return { transfers, emulation };
  }

  const decompiledMessage = decompileTransactionMessage(decompiled);

  for (const instruction of decompiledMessage.instructions) {
    // Simple transfer
    if (SOLANA_PROGRAM_IDS.system.includes(instruction.programAddress)) {
      if (!instruction.data) {
        continue;
      }
      const transferDecoder = getTransferSolInstructionDataDecoder();

      const parsed = transferDecoder.decode(instruction.data);

      const source = instruction.accounts![0].address;
      const destination = instruction.accounts![1].address;

      const isIncoming = address === destination;

      transfers.push(getFakeTransfer(rawTx, false));

      emulation = {
        networkFee: DEFAULT_FEE,
        received: 1n,
        traceOutputs: [],
        activities: [updateActivityMetadata({
          id: '',
          kind: 'transaction',
          timestamp: 0,
          comment: undefined,
          fromAddress: source,
          toAddress: destination,
          amount: parsed.amount,
          slug: SOLANA.slug,
          isIncoming,
          normalizedAddress: isIncoming ? destination : source,
          fee: DEFAULT_FEE,
          status: 'completed',
        })],
        realFee: DEFAULT_FEE,
      };
    }
    // Comment instruction
    if (SOLANA_PROGRAM_IDS.memo.includes(instruction.programAddress)) {
      if (!instruction.data) {
        continue;
      }
      const memoText = Buffer.from(instruction.data).toString('utf-8');

      let activity = emulation?.activities?.[0];
      if (activity && activity.kind === 'transaction') {
        activity = { ...activity, comment: memoText };
        emulation!.activities[0] = activity;
      }
    }
    if (SOLANA_PROGRAM_IDS.token.includes(instruction.programAddress)) {
      if (!instruction.data) {
        continue;
      }
    }
  }

  // Fallback to preview w/o detail & w/ warning
  if (!transfers.length) {
    transfers.push(getFakeTransfer(rawTx, true));
  }
  return { transfers, emulation };
}

export function isComplexTransaction(
  compiled: SolanaCompiledTransaction,
) {
  if ('addressTableLookups' in compiled
    && compiled.addressTableLookups
    && compiled.addressTableLookups.length > 0
  ) {
    return true;
  }

  const isComplex = compiled.instructions.some((inst) => {
    const programAddress = compiled.staticAccounts[inst.programAddressIndex];
    const programIdString = programAddress.toString();

    return !SIMPLE_PROGRAMS.has(programIdString);
  });

  return isComplex;
}

export async function emulateTransaction(transaction: string, network: ApiNetwork) {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'simulateTransaction',
      params: [
        transaction,
        {
          encoding: 'base64',
          replaceRecentBlockhash: true,
          innerInstructions: true,
        },
      ],
    }),
  };

  const response = await fetchJson<SolanaTransactionEmulationResultRaw>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    options,
  );

  return response.result.value;
}
