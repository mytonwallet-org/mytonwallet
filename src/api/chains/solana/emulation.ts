import {
  decompileTransactionMessage,
  getBase64Encoder,
  getCompiledTransactionMessageDecoder,
  getTransactionDecoder,
} from '@solana/kit';

import type { ApiActivity, ApiDappTransfer, ApiEmulationResult, ApiNetwork } from '../../types';
import type { SolanaCompiledTransaction } from './types';

import { SOLANA } from '../../../config';
import {
  ComputeBudgetInstruction,
  identifyComputeBudgetInstruction,
  parseSetComputeUnitPriceInstruction,
} from '../../../lib/solana-program/computeBudget';
import { getTransferSolInstructionDataDecoder, TRANSFER_SOL_DISCRIMINATOR } from '../../../lib/solana-program/system';
import {
  emulateTransaction,
  hasHiddenStakeAuthorityChanges,
  hasHiddenSystemAccountChanges,
  hasHiddenTokenAuthorityChanges,
  parseTokenOperation,
  parseUserPaidTokenAccountRent,
} from './util/programParsers';
import { updateActivityMetadata } from '../../common/helpers';
import { DEFAULT_FEE, SOLANA_PROGRAM_IDS } from './constants';

export { emulateTransaction };

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
    amount: 0n,
    rawPayload: rawTx,
    isDangerous,
    normalizedAddress: '',
    displayedToAddress: '',
    networkFee: 0n,
  };
}

export async function parseTransactionForPreview(rawTx: string, address: string, network: ApiNetwork) {
  const txBytes = getBase64Encoder().encode(rawTx);

  const decoder = getTransactionDecoder();
  const decodedTransaction = decoder.decode(txBytes);
  const decompiled = getCompiledTransactionMessageDecoder().decode(decodedTransaction.messageBytes);

  const transfers: ApiDappTransfer[] = [];
  let emulation: ApiEmulationResult | undefined = undefined;

  if (isComplexTransaction(decompiled)) {
    const emulated = await emulateTransaction(rawTx, network);

    if (hasHiddenSystemAccountChanges(decompiled, emulated?.innerInstructions, address)
      || await hasHiddenTokenAuthorityChanges(decompiled, emulated, address, rawTx, network)
      || await hasHiddenStakeAuthorityChanges(decompiled, emulated?.innerInstructions, address, network)) {
      return { transfers: [getFakeTransfer(rawTx, true)], emulation };
    }

    const tokenOperation = await parseTokenOperation(
      network,
      emulated as any,
      address,
      decompiled.staticAccounts,
      parseUserPaidTokenAccountRent(decompiled, emulated?.innerInstructions, address),
    );

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
            transactionIds: {},
          })],
          realFee: BigInt(swap.networkFee),
        };
      } else {
        const fee = tokenOperation.networkFee;

        emulation = {
          networkFee: fee,
          received: 0n,
          traceOutputs: [],
          // We need to pass TON-like structure, but it's not actual emulation,
          // so we don't have all the fields, but have essential
          activities: tokenOperation.transfers.map((transfer, index) => updateActivityMetadata({
            id: String(index),
            kind: 'transaction',
            timestamp: 0,
            comment: undefined,
            fromAddress: transfer.fromAddress,
            toAddress: transfer.toAddress,
            // Activity preview encodes direction in the sign of `amount`; isIncoming
            // alone is only consulted for zero-amount activities (see
            // formatCurrencyExtended). parseTokenOperation returns an unsigned amount.
            amount: transfer.isIncoming ? transfer.amount : -transfer.amount,
            slug: transfer.slug,
            isIncoming: transfer.isIncoming,
            normalizedAddress: transfer.normalizedAddress,
            fee: BigInt(transfer.fee),
            status: 'completed',
          })),
          realFee: fee,
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
  const activities: ApiActivity[] = [];
  let networkFee = DEFAULT_FEE;
  const hasPriorityFee = decompiledMessage.instructions.some(({ programAddress, data }) => {
    if (!SOLANA_PROGRAM_IDS.computeBudget.includes(programAddress) || !data) return false;

    return identifyComputeBudgetInstruction(data) === ComputeBudgetInstruction.SetComputeUnitPrice
      && parseSetComputeUnitPriceInstruction({ programAddress, data }).data.microLamports > 0n;
  });

  if (hasPriorityFee) {
    const simulatedFee = await emulateTransaction(rawTx, network).then((result) => result?.fee, () => undefined);
    if (simulatedFee === undefined || !Number.isFinite(simulatedFee) || simulatedFee < 0) {
      return { transfers: [getFakeTransfer(rawTx, true)], emulation: undefined };
    }
    networkFee = BigInt(simulatedFee);
  }

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

      // Signing signs every transfer's raw payload, so the transaction gets one transfer however many it moves
      if (!transfers.length) {
        transfers.push(getFakeTransfer(rawTx, false));
      }

      activities.push(updateActivityMetadata({
        id: String(activities.length),
        kind: 'transaction',
        timestamp: 0,
        comment: undefined,
        fromAddress: source,
        toAddress: destination,
        // Sign of `amount` drives the `+`/`−` in the preview; isIncoming is only
        // a zero-amount fallback (see formatCurrencyExtended).
        amount: isIncoming ? parsed.amount : -parsed.amount,
        slug: SOLANA.slug,
        isIncoming,
        normalizedAddress: isIncoming ? source : destination,
        fee: networkFee,
        status: 'completed',
      }));

      emulation = {
        networkFee,
        received: 1n,
        traceOutputs: [],
        activities,
        realFee: networkFee,
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
      } else {
        // Guess that its memo-only transaction
        emulation = {
          networkFee: 0n,
          received: 0n,
          traceOutputs: [],
          activities: [updateActivityMetadata({
            id: '',
            kind: 'transaction',
            timestamp: 0,
            comment: memoText,
            fromAddress: address,
            toAddress: instruction.programAddress,
            amount: 0n,
            slug: SOLANA.slug,
            isIncoming: false,
            normalizedAddress: address,
            fee: 0n,
            status: 'completed',
          })],
          realFee: 0n,
        };
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

    if (SOLANA_PROGRAM_IDS.system.includes(programIdString)) {
      const transferDecoder = getTransferSolInstructionDataDecoder();

      return !inst.data
        || inst.data.length !== transferDecoder.fixedSize
        || (inst.accountIndices?.length ?? 0) < 2
        || transferDecoder.decode(inst.data).discriminator !== TRANSFER_SOL_DISCRIMINATOR;
    }

    if (SOLANA_PROGRAM_IDS.computeBudget.includes(programIdString)) {
      try {
        if (!inst.data) return true;

        const instruction = { programAddress, data: inst.data };

        if (identifyComputeBudgetInstruction(instruction) === ComputeBudgetInstruction.SetComputeUnitPrice) {
          parseSetComputeUnitPriceInstruction(instruction);
        }
        return false;
      } catch {
        return true;
      }
    }

    return !SIMPLE_PROGRAMS.has(programIdString);
  });

  return isComplex;
}
