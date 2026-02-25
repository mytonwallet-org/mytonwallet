import type { Address, FixedSizeDecoder, Instruction, InstructionWithData } from '@solana/kit';
import {
  containsBytes,
  getStructDecoder,
  getStructEncoder,
  getU8Decoder,
  getU8Encoder,
  getU32Decoder,
  getU32Encoder,
  getU64Decoder,
  type ReadonlyUint8Array,
} from '@solana/kit';

export enum ComputeBudgetInstruction {
  RequestUnits,
  RequestHeapFrame,
  SetComputeUnitLimit,
  SetComputeUnitPrice,
  SetLoadedAccountsDataSizeLimit,
}

export const COMPUTE_BUDGET_PROGRAM_ADDRESS
    = 'ComputeBudget111111111111111111111111111111' as Address<'ComputeBudget111111111111111111111111111111'>;

export function identifyComputeBudgetInstruction(
  instruction: { data: ReadonlyUint8Array } | ReadonlyUint8Array,
): ComputeBudgetInstruction {
  const data = 'data' in instruction ? instruction.data : instruction;
  if (containsBytes(data, getU8Encoder().encode(0), 0)) {
    return ComputeBudgetInstruction.RequestUnits;
  }
  if (containsBytes(data, getU8Encoder().encode(1), 0)) {
    return ComputeBudgetInstruction.RequestHeapFrame;
  }
  if (containsBytes(data, getU8Encoder().encode(2), 0)) {
    return ComputeBudgetInstruction.SetComputeUnitLimit;
  }
  if (containsBytes(data, getU8Encoder().encode(3), 0)) {
    return ComputeBudgetInstruction.SetComputeUnitPrice;
  }
  if (containsBytes(data, getU8Encoder().encode(4), 0)) {
    return ComputeBudgetInstruction.SetLoadedAccountsDataSizeLimit;
  }
  throw new Error('The provided instruction could not be identified as a computeBudget instruction.');
}

export type SetComputeUnitPriceInstructionData = {
  discriminator: number;
  /** Transaction compute unit price used for prioritization fees. */
  microLamports: bigint;
};

export type ParsedSetComputeUnitPriceInstruction<TProgram extends string = typeof COMPUTE_BUDGET_PROGRAM_ADDRESS> = {
  programAddress: Address<TProgram>;
  data: SetComputeUnitPriceInstructionData;
};

export function getSetComputeUnitPriceInstructionDataDecoder(): FixedSizeDecoder<SetComputeUnitPriceInstructionData> {
  return getStructDecoder([
    ['discriminator', getU8Decoder()],
    ['microLamports', getU64Decoder()],
  ]);
}

export function getSetComputeUnitLimitInstruction(units: number): Instruction {
  const encoder = getStructEncoder([
    ['discriminator', getU8Encoder()],
    ['units', getU32Encoder()],
  ]);

  return {
    programAddress: COMPUTE_BUDGET_PROGRAM_ADDRESS,
    accounts: [],
    data: encoder.encode({ discriminator: 2, units }),
  };
}

export function parseSetComputeUnitPriceInstruction<TProgram extends string>(
  instruction: Instruction<TProgram> & InstructionWithData<ReadonlyUint8Array>,
): ParsedSetComputeUnitPriceInstruction<TProgram> {
  return {
    programAddress: instruction.programAddress,
    data: getSetComputeUnitPriceInstructionDataDecoder().decode(instruction.data),
  };
}

export type SetComputeUnitLimitInstructionData = {
  discriminator: number;
  /** Transaction-wide compute unit limit. */
  units: number;
};

export type ParsedSetComputeUnitLimitInstruction<TProgram extends string = typeof COMPUTE_BUDGET_PROGRAM_ADDRESS> = {
  programAddress: Address<TProgram>;
  data: SetComputeUnitLimitInstructionData;
};

export function getSetComputeUnitLimitInstructionDataDecoder(): FixedSizeDecoder<SetComputeUnitLimitInstructionData> {
  return getStructDecoder([
    ['discriminator', getU8Decoder()],
    ['units', getU32Decoder()],
  ]);
}

export function parseSetComputeUnitLimitInstruction<TProgram extends string>(
  instruction: Instruction<TProgram> & InstructionWithData<ReadonlyUint8Array>,
): ParsedSetComputeUnitLimitInstruction<TProgram> {
  return {
    programAddress: instruction.programAddress,
    data: getSetComputeUnitLimitInstructionDataDecoder().decode(instruction.data),
  };
}
