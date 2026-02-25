/* eslint-disable no-null/no-null */

import type { FixedSizeDecoder } from '@solana/kit';
import {
  type AccountMeta,
  type AccountSignerMeta,
  type Address,
  type FixedSizeEncoder,
  getStructDecoder,
  getStructEncoder,
  getU32Decoder,
  getU32Encoder,
  getU64Decoder,
  getU64Encoder,
  type Instruction,
  type InstructionWithAccounts,
  type InstructionWithData,
  type ReadonlyUint8Array,
  type TransactionSigner,
  transformEncoder,
  type WritableAccount,
  type WritableSignerAccount,
} from '@solana/kit';

import { getAccountMetaFactory, type ResolvedAccount } from './shared';

const SYSTEM_PROGRAM_ADDRESS = '11111111111111111111111111111111' as Address<'11111111111111111111111111111111'>;
export const TRANSFER_SOL_DISCRIMINATOR = 2;

export type TransferSolInstruction<
  TProgram extends string = typeof SYSTEM_PROGRAM_ADDRESS,
  TAccountSource extends string | AccountMeta<string> = string,
  TAccountDestination extends string | AccountMeta<string> = string,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountSource extends string
        ? WritableSignerAccount<TAccountSource> & AccountSignerMeta<TAccountSource>
        : TAccountSource,
      TAccountDestination extends string ? WritableAccount<TAccountDestination> : TAccountDestination,
      ...TRemainingAccounts,
    ]
  >;

export type TransferSolInstructionDataArgs = { amount: number | bigint };

export type TransferSolInput<TAccountSource extends string = string, TAccountDestination extends string = string> = {
  source: TransactionSigner<TAccountSource>;
  destination: Address<TAccountDestination>;
  amount: TransferSolInstructionDataArgs['amount'];
};

export function getTransferSolInstructionDataEncoder(): FixedSizeEncoder<TransferSolInstructionDataArgs> {
  return transformEncoder(
    getStructEncoder([
      ['discriminator', getU32Encoder()],
      ['amount', getU64Encoder()],
    ]),
    (value) => ({ ...value, discriminator: TRANSFER_SOL_DISCRIMINATOR }),
  );
}

export type TransferSolInstructionData = { discriminator: number; amount: bigint };

export function getTransferSolInstructionDataDecoder(): FixedSizeDecoder<TransferSolInstructionData> {
  return getStructDecoder([
    ['discriminator', getU32Decoder()],
    ['amount', getU64Decoder()],
  ]);
}

export function getTransferSolInstruction<
  TAccountSource extends string,
  TAccountDestination extends string,
  TProgramAddress extends Address = typeof SYSTEM_PROGRAM_ADDRESS,
>(
  input: TransferSolInput<TAccountSource, TAccountDestination>,
  config?: { programAddress?: TProgramAddress },
): TransferSolInstruction<TProgramAddress, TAccountSource, TAccountDestination> {
  // Program address.
  const programAddress = config?.programAddress ?? SYSTEM_PROGRAM_ADDRESS;

  // Original accounts.
  const originalAccounts = {
    source: { value: input.source ?? null, isWritable: true },
    destination: { value: input.destination ?? null, isWritable: true },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  // Original args.
  const args = { ...input };

  const getAccountMeta = getAccountMetaFactory(programAddress, 'omitted');
  return Object.freeze({
    accounts: [getAccountMeta(accounts.source), getAccountMeta(accounts.destination)],
    data: getTransferSolInstructionDataEncoder().encode(args as TransferSolInstructionDataArgs),
    programAddress,
  } as TransferSolInstruction<TProgramAddress, TAccountSource, TAccountDestination>);
}
