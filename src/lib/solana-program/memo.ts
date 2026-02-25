import type {
  Encoder } from '@solana/kit';
import {
  type AccountMeta,
  AccountRole,
  type Address,
  getStructEncoder,
  getUtf8Encoder,
  type Instruction,
  type InstructionWithAccounts,
  type InstructionWithData,
  type ReadonlyUint8Array,
  type TransactionSigner,
} from '@solana/kit';

const MEMO_PROGRAM_ADDRESS
  = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr' as Address<'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr'>;

export type AddMemoInstructionData = { memo: string };

export type AddMemoInput = {
  memo: AddMemoInstructionData['memo'];
  signers?: Array<TransactionSigner>;
};

export type AddMemoInstruction<
  TProgram extends string = typeof MEMO_PROGRAM_ADDRESS,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<TRemainingAccounts>;

export function getAddMemoInstructionDataEncoder(): Encoder<AddMemoInstructionData> {
  return getStructEncoder([['memo', getUtf8Encoder()]]);
}

export function getAddMemoInstruction<
  TProgramAddress extends Address = typeof MEMO_PROGRAM_ADDRESS,
>(
  input: AddMemoInput,
  config?: { programAddress?: TProgramAddress },
): AddMemoInstruction<TProgramAddress> {
  // Program address.
  const programAddress = config?.programAddress ?? MEMO_PROGRAM_ADDRESS;

  // Original args.
  const args = { ...input };

  // Remaining accounts.
  const remainingAccounts: AccountMeta[] = (args.signers ?? []).map(
    (signer) => ({
      address: signer.address,
      role: AccountRole.READONLY_SIGNER,
      signer,
    }),
  );

  return Object.freeze({
    accounts: remainingAccounts,
    data: getAddMemoInstructionDataEncoder().encode(
      args,
    ),
    programAddress,
  } as AddMemoInstruction<TProgramAddress>);
}
