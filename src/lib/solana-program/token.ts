/* eslint-disable no-null/no-null */

import type {
  AccountMeta,
  AccountSignerMeta,
  FixedSizeCodec,
  FixedSizeDecoder,
  FixedSizeEncoder,
  Instruction,
  InstructionWithAccounts,
  InstructionWithData,
  ReadonlyAccount,
  ReadonlySignerAccount,
  ReadonlyUint8Array,
  TransactionSigner,
  WritableAccount,
  WritableSignerAccount } from '@solana/kit';
import {
  AccountRole,
  type Address,
  combineCodec,
  getAddressEncoder,
  getProgramDerivedAddress,
  getStructDecoder,
  getStructEncoder,
  getU8Decoder,
  getU8Encoder,
  getU64Encoder,
  type ProgramDerivedAddress,
  transformEncoder,
} from '@solana/kit';

import type { ResolvedAccount } from './shared';

import { expectAddress, getAccountMetaFactory } from './shared';

export const TOKEN_PROGRAM_ADDRESS
  = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA' as Address<'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'>;

export const ASSOCIATED_TOKEN_PROGRAM_ADDRESS
  = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL' as Address<'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'>;

export const CREATE_ASSOCIATED_TOKEN_IDEMPOTENT_DISCRIMINATOR = 1;

export type AssociatedTokenSeeds = {
  /** The wallet address of the associated token account */
  owner: Address;
  /** The address of the token program to use */
  tokenProgram: Address;
  /** The mint address of the associated token account */
  mint: Address;
};

export type CreateAssociatedTokenInstructionData = { discriminator: number };

export type CreateAssociatedTokenIdempotentInstruction<
  TProgram extends string = typeof ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  TAccountPayer extends string | AccountMeta<string> = string,
  TAccountAta extends string | AccountMeta<string> = string,
  TAccountOwner extends string | AccountMeta<string> = string,
  TAccountMint extends string | AccountMeta<string> = string,
  TAccountSystemProgram extends
  | string
  | AccountMeta<string> = '11111111111111111111111111111111',
  TAccountTokenProgram extends
  | string
  | AccountMeta<string> = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountPayer extends string ? WritableSignerAccount<TAccountPayer> &
      AccountSignerMeta<TAccountPayer>
        : TAccountPayer,
      TAccountAta extends string ? WritableAccount<TAccountAta> : TAccountAta,
      TAccountOwner extends string
        ? ReadonlyAccount<TAccountOwner>
        : TAccountOwner,
      TAccountMint extends string
        ? ReadonlyAccount<TAccountMint>
        : TAccountMint,
      TAccountSystemProgram extends string
        ? ReadonlyAccount<TAccountSystemProgram>
        : TAccountSystemProgram,
      TAccountTokenProgram extends string
        ? ReadonlyAccount<TAccountTokenProgram>
        : TAccountTokenProgram,
      ...TRemainingAccounts,
    ]
  >;

export type CreateAssociatedTokenIdempotentAsyncInput<
  TAccountPayer extends string = string,
  TAccountAta extends string = string,
  TAccountOwner extends string = string,
  TAccountMint extends string = string,
  TAccountSystemProgram extends string = string,
  TAccountTokenProgram extends string = string,
> = {
  /** Funding account (must be a system account) */
  payer: TransactionSigner<TAccountPayer>;
  /** Associated token account address to be created */
  ata?: Address<TAccountAta>;
  /** Wallet address for the new associated token account */
  owner: Address<TAccountOwner>;
  /** The token mint for the new associated token account */
  mint: Address<TAccountMint>;
  /** System program */
  systemProgram?: Address<TAccountSystemProgram>;
  /** SPL Token program */
  tokenProgram?: Address<TAccountTokenProgram>;
};

export async function findAssociatedTokenPda(
  seeds: AssociatedTokenSeeds,
  config: { programAddress?: Address | undefined } = {},
): Promise<ProgramDerivedAddress> {
  const {
    programAddress = ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  } = config;
  return await getProgramDerivedAddress({
    programAddress,
    seeds: [
      getAddressEncoder().encode(seeds.owner),
      getAddressEncoder().encode(seeds.tokenProgram),
      getAddressEncoder().encode(seeds.mint),
    ],
  });
}

// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export type CreateAssociatedTokenIdempotentInstructionDataArgs = {};

export function getCreateAssociatedTokenIdempotentInstructionDataEncoder():
FixedSizeEncoder<CreateAssociatedTokenIdempotentInstructionDataArgs> {
  return transformEncoder(
    getStructEncoder([['discriminator', getU8Encoder()]]),
    (value) => ({
      ...value,
      discriminator: CREATE_ASSOCIATED_TOKEN_IDEMPOTENT_DISCRIMINATOR,
    }),
  );
}

export async function getCreateAssociatedTokenIdempotentInstructionAsync<
  TAccountPayer extends string,
  TAccountAta extends string,
  TAccountOwner extends string,
  TAccountMint extends string,
  TAccountSystemProgram extends string,
  TAccountTokenProgram extends string,
  TProgramAddress extends Address = typeof ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
>(
  input: CreateAssociatedTokenIdempotentAsyncInput<
    TAccountPayer,
    TAccountAta,
    TAccountOwner,
    TAccountMint,
    TAccountSystemProgram,
    TAccountTokenProgram
  >,
  config?: { programAddress?: TProgramAddress },
): Promise<
    CreateAssociatedTokenIdempotentInstruction<
      TProgramAddress,
      TAccountPayer,
      TAccountAta,
      TAccountOwner,
      TAccountMint,
      TAccountSystemProgram,
      TAccountTokenProgram
    >
  > {
  const programAddress
    = config?.programAddress ?? ASSOCIATED_TOKEN_PROGRAM_ADDRESS;

  const originalAccounts = {
    payer: { value: input.payer ?? null, isWritable: true },
    ata: { value: input.ata ?? null, isWritable: true },
    owner: { value: input.owner ?? null, isWritable: false },
    mint: { value: input.mint ?? null, isWritable: false },
    systemProgram: { value: input.systemProgram ?? null, isWritable: false },
    tokenProgram: { value: input.tokenProgram ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<
    keyof typeof originalAccounts,
    ResolvedAccount
  >;

  // Resolve default values
  if (!accounts.tokenProgram.value) {
    accounts.tokenProgram.value
      = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA' as Address<'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'>;
  }
  if (!accounts.ata.value) {
    accounts.ata.value = await findAssociatedTokenPda({
      owner: expectAddress(accounts.owner.value),
      tokenProgram: expectAddress(accounts.tokenProgram.value),
      mint: expectAddress(accounts.mint.value),
    });
  }
  if (!accounts.systemProgram.value) {
    accounts.systemProgram.value
      = '11111111111111111111111111111111' as Address<'11111111111111111111111111111111'>;
  }

  const getAccountMeta = getAccountMetaFactory(programAddress, 'programId');
  return Object.freeze({
    accounts: [
      getAccountMeta(accounts.payer),
      getAccountMeta(accounts.ata),
      getAccountMeta(accounts.owner),
      getAccountMeta(accounts.mint),
      getAccountMeta(accounts.systemProgram),
      getAccountMeta(accounts.tokenProgram),
    ],
    data: getCreateAssociatedTokenIdempotentInstructionDataEncoder().encode({}),
    programAddress,
  } as CreateAssociatedTokenIdempotentInstruction<
    TProgramAddress,
    TAccountPayer,
    TAccountAta,
    TAccountOwner,
    TAccountMint,
    TAccountSystemProgram,
    TAccountTokenProgram
  >);
}

export type TransferInstructionDataArgs = {
  /** The amount of tokens to transfer */
  amount: number | bigint;
};

export type TransferInput<
  TAccountSource extends string = string,
  TAccountDestination extends string = string,
  TAccountAuthority extends string = string,
> = {
  /** The source account */
  source: Address<TAccountSource>;
  /** The destination account */
  destination: Address<TAccountDestination>;
  /** The source account's owner/delegate or its multisignature account */
  authority: Address<TAccountAuthority> | TransactionSigner<TAccountAuthority>;
  amount: TransferInstructionDataArgs['amount'];
  multiSigners?: Array<TransactionSigner>;
};

export type TransferInstruction<
  TProgram extends string = typeof TOKEN_PROGRAM_ADDRESS,
  TAccountSource extends string | AccountMeta<string> = string,
  TAccountDestination extends string | AccountMeta<string> = string,
  TAccountAuthority extends string | AccountMeta<string> = string,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountSource extends string
        ? WritableAccount<TAccountSource>
        : TAccountSource,
      TAccountDestination extends string
        ? WritableAccount<TAccountDestination>
        : TAccountDestination,
      TAccountAuthority extends string
        ? ReadonlyAccount<TAccountAuthority>
        : TAccountAuthority,
      ...TRemainingAccounts,
    ]
  >;

export const TRANSFER_DISCRIMINATOR = 3;

export function getTransferInstructionDataEncoder(): FixedSizeEncoder<TransferInstructionDataArgs> {
  return transformEncoder(
    getStructEncoder([
      ['discriminator', getU8Encoder()],
      ['amount', getU64Encoder()],
    ]),
    (value) => ({ ...value, discriminator: TRANSFER_DISCRIMINATOR }),
  );
}

export function getTransferInstruction<
  TAccountSource extends string,
  TAccountDestination extends string,
  TAccountAuthority extends string,
  TProgramAddress extends Address = typeof TOKEN_PROGRAM_ADDRESS,
>(
  input: TransferInput<TAccountSource, TAccountDestination, TAccountAuthority>,
  config?: { programAddress?: TProgramAddress },
): TransferInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority> ?
    ReadonlySignerAccount<TAccountAuthority> &
    AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  > {
  const programAddress = config?.programAddress ?? TOKEN_PROGRAM_ADDRESS;

  const originalAccounts = {
    source: { value: input.source ?? null, isWritable: true },
    destination: { value: input.destination ?? null, isWritable: true },
    authority: { value: input.authority ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<
    keyof typeof originalAccounts,
    ResolvedAccount
  >;

  const args = { ...input };

  const remainingAccounts: AccountMeta[] = (args.multiSigners ?? []).map(
    (signer) => ({
      address: signer.address,
      role: AccountRole.READONLY_SIGNER,
      signer,
    }),
  );

  const getAccountMeta = getAccountMetaFactory(programAddress, 'programId');
  return Object.freeze({
    accounts: [
      getAccountMeta(accounts.source),
      getAccountMeta(accounts.destination),
      getAccountMeta(accounts.authority),
      ...remainingAccounts,
    ],
    data: getTransferInstructionDataEncoder().encode(
      args as TransferInstructionDataArgs,
    ),
    programAddress,
  } as TransferInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority> ?
    ReadonlySignerAccount<TAccountAuthority> &
    AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  >);
}

export const CLOSE_ACCOUNT_DISCRIMINATOR = 9;

export function getCloseAccountDiscriminatorBytes() {
  return getU8Encoder().encode(CLOSE_ACCOUNT_DISCRIMINATOR);
}

export type CloseAccountInstruction<
  TProgram extends string = typeof TOKEN_PROGRAM_ADDRESS,
  TAccountAccount extends string | AccountMeta<string> = string,
  TAccountDestination extends string | AccountMeta<string> = string,
  TAccountOwner extends string | AccountMeta<string> = string,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountAccount extends string ? WritableAccount<TAccountAccount> : TAccountAccount,
      TAccountDestination extends string ? WritableAccount<TAccountDestination> : TAccountDestination,
      TAccountOwner extends string ? ReadonlyAccount<TAccountOwner> : TAccountOwner,
      ...TRemainingAccounts,
    ]
  >;

export type CloseAccountInstructionData = { discriminator: number };

// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export type CloseAccountInstructionDataArgs = {};

export function getCloseAccountInstructionDataEncoder(): FixedSizeEncoder<CloseAccountInstructionDataArgs> {
  return transformEncoder(getStructEncoder([['discriminator', getU8Encoder()]]), (value) => ({
    ...value,
    discriminator: CLOSE_ACCOUNT_DISCRIMINATOR,
  }));
}

export function getCloseAccountInstructionDataDecoder(): FixedSizeDecoder<CloseAccountInstructionData> {
  return getStructDecoder([['discriminator', getU8Decoder()]]);
}

export function getCloseAccountInstructionDataCodec(): FixedSizeCodec<
  CloseAccountInstructionDataArgs,
  CloseAccountInstructionData
> {
  return combineCodec(getCloseAccountInstructionDataEncoder(), getCloseAccountInstructionDataDecoder());
}

export type CloseAccountInput<
  TAccountAccount extends string = string,
  TAccountDestination extends string = string,
  TAccountOwner extends string = string,
> = {
  /** The account to close */
  account: Address<TAccountAccount>;
  /** The destination account */
  destination: Address<TAccountDestination>;
  /** The account's owner or its multisignature account */
  owner: Address<TAccountOwner> | TransactionSigner<TAccountOwner>;
  multiSigners?: Array<TransactionSigner>;
};

export function getCloseAccountInstruction<
  TAccountAccount extends string,
  TAccountDestination extends string,
  TAccountOwner extends string,
  TProgramAddress extends Address = typeof TOKEN_PROGRAM_ADDRESS,
>(
  input: CloseAccountInput<TAccountAccount, TAccountDestination, TAccountOwner>,
  config?: { programAddress?: TProgramAddress },
): CloseAccountInstruction<
    TProgramAddress,
    TAccountAccount,
    TAccountDestination,
    (typeof input)['owner'] extends TransactionSigner<TAccountOwner>
      ? ReadonlySignerAccount<TAccountOwner> & AccountSignerMeta<TAccountOwner>
      : TAccountOwner
  > {
  const programAddress = config?.programAddress ?? TOKEN_PROGRAM_ADDRESS;

  const originalAccounts = {
    account: { value: input.account ?? null, isWritable: true },
    destination: { value: input.destination ?? null, isWritable: true },
    owner: { value: input.owner ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  const args = { ...input };

  const remainingAccounts: AccountMeta[] = (args.multiSigners ?? []).map((signer) => ({
    address: signer.address,
    role: AccountRole.READONLY_SIGNER,
    signer,
  }));

  const getAccountMeta = getAccountMetaFactory(programAddress, 'programId');
  return Object.freeze({
    accounts: [
      getAccountMeta(accounts.account),
      getAccountMeta(accounts.destination),
      getAccountMeta(accounts.owner),
      ...remainingAccounts,
    ],
    data: getCloseAccountInstructionDataEncoder().encode({}),
    programAddress,
  } as CloseAccountInstruction<
    TProgramAddress,
    TAccountAccount,
    TAccountDestination,
    (typeof input)['owner'] extends TransactionSigner<TAccountOwner>
      ? ReadonlySignerAccount<TAccountOwner> & AccountSignerMeta<TAccountOwner>
      : TAccountOwner
  >);
}

export type ParsedCloseAccountInstruction<
  TProgram extends string = typeof TOKEN_PROGRAM_ADDRESS,
  TAccountMetas extends readonly AccountMeta[] = readonly AccountMeta[],
> = {
  programAddress: Address<TProgram>;
  accounts: {
    /** The account to close */
    account: TAccountMetas[0];
    /** The destination account */
    destination: TAccountMetas[1];
    /** The account's owner or its multisignature account */
    owner: TAccountMetas[2];
  };
  data: CloseAccountInstructionData;
};

export function parseCloseAccountInstruction<TProgram extends string, TAccountMetas extends readonly AccountMeta[]>(
  instruction: Instruction<TProgram> &
    InstructionWithAccounts<TAccountMetas> &
    InstructionWithData<ReadonlyUint8Array>,
): ParsedCloseAccountInstruction<TProgram, TAccountMetas> {
  if (instruction.accounts.length < 3) {
    // TODO: Coded error.
    throw new Error('Not enough accounts');
  }
  let accountIndex = 0;
  const getNextAccount = () => {
    const accountMeta = (instruction.accounts as TAccountMetas)[accountIndex];
    accountIndex += 1;
    return accountMeta;
  };
  return {
    programAddress: instruction.programAddress,
    accounts: { account: getNextAccount(), destination: getNextAccount(), owner: getNextAccount() },
    data: getCloseAccountInstructionDataDecoder().decode(instruction.data),
  };
}
