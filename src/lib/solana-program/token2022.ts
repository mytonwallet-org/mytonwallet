/* eslint-disable no-null/no-null */
import type {
  Address,
  FixedSizeCodec,
  FixedSizeDecoder,
  FixedSizeEncoder,
  ProgramDerivedAddress,
  ReadonlyAccount,
  WritableAccount,
  WritableSignerAccount,
} from '@solana/kit';
import {
  type AccountMeta,
  AccountRole,
  type AccountSignerMeta,
  combineCodec,
  getAddressEncoder,
  getProgramDerivedAddress,
  getStructDecoder,
  getStructEncoder,
  getU8Decoder,
  getU8Encoder,
  getU64Decoder,
  getU64Encoder,
  type Instruction,
  type InstructionWithAccounts,
  type InstructionWithData,
  type ReadonlySignerAccount,
  type ReadonlyUint8Array,
  type TransactionSigner,
  transformEncoder,
} from '@solana/kit';

import type { ResolvedAccount } from './shared';

import { expectAddress, getAccountMetaFactory } from './shared';

const TOKEN_2022_PROGRAM_ADDRESS
    = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb' as Address<'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'>;

const ASSOCIATED_TOKEN_PROGRAM_ADDRESS
    = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL' as Address<'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'>;

type AssociatedTokenSeeds = {
  /** The wallet address of the associated token account. */
  owner: Address;
  /** The address of the token program to use. */
  tokenProgram: Address;
  /** The mint address of the associated token account. */
  mint: Address;
};

export async function findAssociatedToken2022Pda(
  seeds: AssociatedTokenSeeds,
  config: { programAddress?: Address | undefined } = {},
): Promise<ProgramDerivedAddress> {
  const {
    programAddress =
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL' as Address<'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'>,
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

export const TRANSFER_DISCRIMINATOR = 3;

export function getTransferDiscriminatorBytes() {
  return getU8Encoder().encode(TRANSFER_DISCRIMINATOR);
}

export type TransferInstruction<
  TProgram extends string = typeof TOKEN_2022_PROGRAM_ADDRESS,
  TAccountSource extends string | AccountMeta<string> = string,
  TAccountDestination extends string | AccountMeta<string> = string,
  TAccountAuthority extends string | AccountMeta<string> = string,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountSource extends string ? WritableAccount<TAccountSource> : TAccountSource,
      TAccountDestination extends string ? WritableAccount<TAccountDestination> : TAccountDestination,
      TAccountAuthority extends string ? ReadonlyAccount<TAccountAuthority> : TAccountAuthority,
      ...TRemainingAccounts,
    ]
  >;

export type TransferInstructionData = {
  discriminator: number;
  /** The amount of tokens to transfer. */
  amount: bigint;
};

export type TransferInstructionDataArgs = {
  /** The amount of tokens to transfer. */
  amount: number | bigint;
};

export function getTransferInstructionDataEncoder(): FixedSizeEncoder<TransferInstructionDataArgs> {
  return transformEncoder(
    getStructEncoder([
      ['discriminator', getU8Encoder()],
      ['amount', getU64Encoder()],
    ]),
    (value) => ({ ...value, discriminator: TRANSFER_DISCRIMINATOR }),
  );
}

export function getTransferInstructionDataDecoder(): FixedSizeDecoder<TransferInstructionData> {
  return getStructDecoder([
    ['discriminator', getU8Decoder()],
    ['amount', getU64Decoder()],
  ]);
}

export function getTransferInstructionDataCodec(): FixedSizeCodec<
  TransferInstructionDataArgs,
  TransferInstructionData
> {
  return combineCodec(getTransferInstructionDataEncoder(), getTransferInstructionDataDecoder());
}

export type TransferInput<
  TAccountSource extends string = string,
  TAccountDestination extends string = string,
  TAccountAuthority extends string = string,
> = {
  /** The source account. */
  source: Address<TAccountSource>;
  /** The destination account. */
  destination: Address<TAccountDestination>;
  /** The source account's owner/delegate or its multisignature account. */
  authority: Address<TAccountAuthority> | TransactionSigner<TAccountAuthority>;
  amount: TransferInstructionDataArgs['amount'];
  multiSigners?: Array<TransactionSigner>;
};

export function getTransferToken2022Instruction<
  TAccountSource extends string,
  TAccountDestination extends string,
  TAccountAuthority extends string,
  TProgramAddress extends Address = typeof TOKEN_2022_PROGRAM_ADDRESS,
>(
  input: TransferInput<TAccountSource, TAccountDestination, TAccountAuthority>,
  config?: { programAddress?: TProgramAddress },
): TransferInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority>
      ? ReadonlySignerAccount<TAccountAuthority> & AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  > {
  // Program address.
  const programAddress = config?.programAddress ?? TOKEN_2022_PROGRAM_ADDRESS;

  // Original accounts.
  const originalAccounts = {
    source: { value: input.source ?? null, isWritable: true },
    destination: { value: input.destination ?? null, isWritable: true },
    authority: { value: input.authority ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  // Original args.
  const args = { ...input };

  // Remaining accounts.
  const remainingAccounts: AccountMeta[] = (args.multiSigners ?? []).map((signer) => ({
    address: signer.address,
    role: AccountRole.READONLY_SIGNER,
    signer,
  }));

  const getAccountMeta = getAccountMetaFactory(programAddress, 'programId');
  return Object.freeze({
    accounts: [
      getAccountMeta(accounts.source),
      getAccountMeta(accounts.destination),
      getAccountMeta(accounts.authority),
      ...remainingAccounts,
    ],
    data: getTransferInstructionDataEncoder().encode(args as TransferInstructionDataArgs),
    programAddress,
  } as TransferInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority>
      ? ReadonlySignerAccount<TAccountAuthority> & AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  >);
}

export type ParsedTransferInstruction<
  TProgram extends string = typeof TOKEN_2022_PROGRAM_ADDRESS,
  TAccountMetas extends readonly AccountMeta[] = readonly AccountMeta[],
> = {
  programAddress: Address<TProgram>;
  accounts: {
    /** The source account. */
    source: TAccountMetas[0];
    /** The destination account. */
    destination: TAccountMetas[1];
    /** The source account's owner/delegate or its multisignature account. */
    authority: TAccountMetas[2];
  };
  data: TransferInstructionData;
};

export function parseTransferInstruction<TProgram extends string, TAccountMetas extends readonly AccountMeta[]>(
  instruction: Instruction<TProgram> &
    InstructionWithAccounts<TAccountMetas> &
    InstructionWithData<ReadonlyUint8Array>,
): ParsedTransferInstruction<TProgram, TAccountMetas> {
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
    accounts: { source: getNextAccount(), destination: getNextAccount(), authority: getNextAccount() },
    data: getTransferInstructionDataDecoder().decode(instruction.data),
  };
}

export const CREATE_ASSOCIATED_TOKEN_IDEMPOTENT_DISCRIMINATOR = 1;

export function getCreateAssociatedTokenIdempotentDiscriminatorBytes() {
  return getU8Encoder().encode(CREATE_ASSOCIATED_TOKEN_IDEMPOTENT_DISCRIMINATOR);
}

export type CreateAssociatedTokenIdempotentInstruction<
  TProgram extends string = typeof ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  TAccountPayer extends string | AccountMeta<string> = string,
  TAccountAta extends string | AccountMeta<string> = string,
  TAccountOwner extends string | AccountMeta<string> = string,
  TAccountMint extends string | AccountMeta<string> = string,
  TAccountSystemProgram extends string | AccountMeta<string> = '11111111111111111111111111111111',
  TAccountTokenProgram extends string | AccountMeta<string> = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb',
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountPayer extends string
        ? WritableSignerAccount<TAccountPayer> & AccountSignerMeta<TAccountPayer>
        : TAccountPayer,
      TAccountAta extends string ? WritableAccount<TAccountAta> : TAccountAta,
      TAccountOwner extends string ? ReadonlyAccount<TAccountOwner> : TAccountOwner,
      TAccountMint extends string ? ReadonlyAccount<TAccountMint> : TAccountMint,
      TAccountSystemProgram extends string ? ReadonlyAccount<TAccountSystemProgram> : TAccountSystemProgram,
      TAccountTokenProgram extends string ? ReadonlyAccount<TAccountTokenProgram> : TAccountTokenProgram,
      ...TRemainingAccounts,
    ]
  >;

export type CreateAssociatedTokenIdempotentInstructionData = { discriminator: number };

// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export type CreateAssociatedTokenIdempotentInstructionDataArgs = {};

export function getCreateAssociatedTokenIdempotentInstructionDataEncoder():
FixedSizeEncoder<CreateAssociatedTokenIdempotentInstructionDataArgs> {
  return transformEncoder(getStructEncoder([['discriminator', getU8Encoder()]]), (value) => ({
    ...value,
    discriminator: CREATE_ASSOCIATED_TOKEN_IDEMPOTENT_DISCRIMINATOR,
  }));
}

export function getCreateAssociatedToken2022IdempotentInstructionDataDecoder():
FixedSizeDecoder<CreateAssociatedTokenIdempotentInstructionData> {
  return getStructDecoder([['discriminator', getU8Decoder()]]);
}

export function getCreateAssociatedToken2022IdempotentInstructionDataCodec(): FixedSizeCodec<
  CreateAssociatedTokenIdempotentInstructionDataArgs,
  CreateAssociatedTokenIdempotentInstructionData
> {
  return combineCodec(
    getCreateAssociatedTokenIdempotentInstructionDataEncoder(),
    getCreateAssociatedToken2022IdempotentInstructionDataDecoder(),
  );
}

export type CreateAssociatedTokenIdempotentAsyncInput<
  TAccountPayer extends string = string,
  TAccountAta extends string = string,
  TAccountOwner extends string = string,
  TAccountMint extends string = string,
  TAccountSystemProgram extends string = string,
  TAccountTokenProgram extends string = string,
> = {
  /** Funding account (must be a system account). */
  payer: TransactionSigner<TAccountPayer>;
  /** Associated token account address to be created. */
  ata?: Address<TAccountAta>;
  /** Wallet address for the new associated token account. */
  owner: Address<TAccountOwner>;
  /** The token mint for the new associated token account. */
  mint: Address<TAccountMint>;
  /** System program. */
  systemProgram?: Address<TAccountSystemProgram>;
  /** SPL Token program. */
  tokenProgram?: Address<TAccountTokenProgram>;
};

export async function getCreateAssociatedToken2022IdempotentInstructionAsync<
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
  // Program address.
  const programAddress = config?.programAddress ?? ASSOCIATED_TOKEN_PROGRAM_ADDRESS;

  // Original accounts.
  const originalAccounts = {
    payer: { value: input.payer ?? null, isWritable: true },
    ata: { value: input.ata ?? null, isWritable: true },
    owner: { value: input.owner ?? null, isWritable: false },
    mint: { value: input.mint ?? null, isWritable: false },
    systemProgram: { value: input.systemProgram ?? null, isWritable: false },
    tokenProgram: { value: input.tokenProgram ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  // Resolve default values.
  if (!accounts.tokenProgram.value) {
    accounts.tokenProgram.value
            = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb' as Address<'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'>;
  }
  if (!accounts.ata.value) {
    accounts.ata.value = await findAssociatedToken2022Pda({
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

export type CreateAssociatedTokenIdempotentInput<
  TAccountPayer extends string = string,
  TAccountAta extends string = string,
  TAccountOwner extends string = string,
  TAccountMint extends string = string,
  TAccountSystemProgram extends string = string,
  TAccountTokenProgram extends string = string,
> = {
  /** Funding account (must be a system account). */
  payer: TransactionSigner<TAccountPayer>;
  /** Associated token account address to be created. */
  ata: Address<TAccountAta>;
  /** Wallet address for the new associated token account. */
  owner: Address<TAccountOwner>;
  /** The token mint for the new associated token account. */
  mint: Address<TAccountMint>;
  /** System program. */
  systemProgram?: Address<TAccountSystemProgram>;
  /** SPL Token program. */
  tokenProgram?: Address<TAccountTokenProgram>;
};

export function getCreateAssociatedTokenIdempotentInstruction<
  TAccountPayer extends string,
  TAccountAta extends string,
  TAccountOwner extends string,
  TAccountMint extends string,
  TAccountSystemProgram extends string,
  TAccountTokenProgram extends string,
  TProgramAddress extends Address = typeof ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
>(
  input: CreateAssociatedTokenIdempotentInput<
    TAccountPayer,
    TAccountAta,
    TAccountOwner,
    TAccountMint,
    TAccountSystemProgram,
    TAccountTokenProgram
  >,
  config?: { programAddress?: TProgramAddress },
): CreateAssociatedTokenIdempotentInstruction<
    TProgramAddress,
    TAccountPayer,
    TAccountAta,
    TAccountOwner,
    TAccountMint,
    TAccountSystemProgram,
    TAccountTokenProgram
  > {
  // Program address.
  const programAddress = config?.programAddress ?? ASSOCIATED_TOKEN_PROGRAM_ADDRESS;

  // Original accounts.
  const originalAccounts = {
    payer: { value: input.payer ?? null, isWritable: true },
    ata: { value: input.ata ?? null, isWritable: true },
    owner: { value: input.owner ?? null, isWritable: false },
    mint: { value: input.mint ?? null, isWritable: false },
    systemProgram: { value: input.systemProgram ?? null, isWritable: false },
    tokenProgram: { value: input.tokenProgram ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  // Resolve default values.
  if (!accounts.tokenProgram.value) {
    accounts.tokenProgram.value
            = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb' as Address<'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'>;
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

export type ParsedCreateAssociatedTokenIdempotentInstruction<
  TProgram extends string = typeof ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  TAccountMetas extends readonly AccountMeta[] = readonly AccountMeta[],
> = {
  programAddress: Address<TProgram>;
  accounts: {
    /** Funding account (must be a system account). */
    payer: TAccountMetas[0];
    /** Associated token account address to be created. */
    ata: TAccountMetas[1];
    /** Wallet address for the new associated token account. */
    owner: TAccountMetas[2];
    /** The token mint for the new associated token account. */
    mint: TAccountMetas[3];
    /** System program. */
    systemProgram: TAccountMetas[4];
    /** SPL Token program. */
    tokenProgram: TAccountMetas[5];
  };
  data: CreateAssociatedTokenIdempotentInstructionData;
};

export function parseCreateAssociatedTokenIdempotentInstruction<
  TProgram extends string,
  TAccountMetas extends readonly AccountMeta[],
>(
  instruction: Instruction<TProgram> &
    InstructionWithAccounts<TAccountMetas> &
    InstructionWithData<ReadonlyUint8Array>,
): ParsedCreateAssociatedTokenIdempotentInstruction<TProgram, TAccountMetas> {
  if (instruction.accounts.length < 6) {
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
    accounts: {
      payer: getNextAccount(),
      ata: getNextAccount(),
      owner: getNextAccount(),
      mint: getNextAccount(),
      systemProgram: getNextAccount(),
      tokenProgram: getNextAccount(),
    },
    data: getCreateAssociatedToken2022IdempotentInstructionDataDecoder().decode(instruction.data),
  };
}

export const TRANSFER_CHECKED_DISCRIMINATOR = 12;

export function getTransferCheckedDiscriminatorBytes() {
  return getU8Encoder().encode(TRANSFER_CHECKED_DISCRIMINATOR);
}

export type TransferCheckedInstruction<
  TProgram extends string = typeof TOKEN_2022_PROGRAM_ADDRESS,
  TAccountSource extends string | AccountMeta<string> = string,
  TAccountMint extends string | AccountMeta<string> = string,
  TAccountDestination extends string | AccountMeta<string> = string,
  TAccountAuthority extends string | AccountMeta<string> = string,
  TRemainingAccounts extends readonly AccountMeta<string>[] = [],
> = Instruction<TProgram> &
  InstructionWithData<ReadonlyUint8Array> &
  InstructionWithAccounts<
    [
      TAccountSource extends string ? WritableAccount<TAccountSource> : TAccountSource,
      TAccountMint extends string ? ReadonlyAccount<TAccountMint> : TAccountMint,
      TAccountDestination extends string ? WritableAccount<TAccountDestination> : TAccountDestination,
      TAccountAuthority extends string ? ReadonlyAccount<TAccountAuthority> : TAccountAuthority,
      ...TRemainingAccounts,
    ]
  >;

export type TransferCheckedInstructionData = {
  discriminator: number;
  /** The amount of tokens to transfer. */
  amount: bigint;
  /** Expected number of base 10 digits to the right of the decimal place. */
  decimals: number;
};

export type TransferCheckedInstructionDataArgs = {
  /** The amount of tokens to transfer. */
  amount: number | bigint;
  /** Expected number of base 10 digits to the right of the decimal place. */
  decimals: number;
};

export function getTransferCheckedInstructionDataEncoder(): FixedSizeEncoder<TransferCheckedInstructionDataArgs> {
  return transformEncoder(
    getStructEncoder([
      ['discriminator', getU8Encoder()],
      ['amount', getU64Encoder()],
      ['decimals', getU8Encoder()],
    ]),
    (value) => ({ ...value, discriminator: TRANSFER_CHECKED_DISCRIMINATOR }),
  );
}

export function getTransferCheckedInstructionDataDecoder(): FixedSizeDecoder<TransferCheckedInstructionData> {
  return getStructDecoder([
    ['discriminator', getU8Decoder()],
    ['amount', getU64Decoder()],
    ['decimals', getU8Decoder()],
  ]);
}

export function getTransferCheckedInstructionDataCodec(): FixedSizeCodec<
  TransferCheckedInstructionDataArgs,
  TransferCheckedInstructionData
> {
  return combineCodec(getTransferCheckedInstructionDataEncoder(), getTransferCheckedInstructionDataDecoder());
}

export type TransferCheckedInput<
  TAccountSource extends string = string,
  TAccountMint extends string = string,
  TAccountDestination extends string = string,
  TAccountAuthority extends string = string,
> = {
  /** The source account. */
  source: Address<TAccountSource>;
  /** The token mint. */
  mint: Address<TAccountMint>;
  /** The destination account. */
  destination: Address<TAccountDestination>;
  /** The source account's owner/delegate or its multisignature account. */
  authority: Address<TAccountAuthority> | TransactionSigner<TAccountAuthority>;
  amount: TransferCheckedInstructionDataArgs['amount'];
  decimals: TransferCheckedInstructionDataArgs['decimals'];
  multiSigners?: Array<TransactionSigner>;
};

export function getTransferCheckedInstruction<
  TAccountSource extends string,
  TAccountMint extends string,
  TAccountDestination extends string,
  TAccountAuthority extends string,
  TProgramAddress extends Address = typeof TOKEN_2022_PROGRAM_ADDRESS,
>(
  input: TransferCheckedInput<TAccountSource, TAccountMint, TAccountDestination, TAccountAuthority>,
  config?: { programAddress?: TProgramAddress },
): TransferCheckedInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountMint,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority>
      ? ReadonlySignerAccount<TAccountAuthority> & AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  > {
  // Program address.
  const programAddress = config?.programAddress ?? TOKEN_2022_PROGRAM_ADDRESS;

  // Original accounts.
  const originalAccounts = {
    source: { value: input.source ?? null, isWritable: true },
    mint: { value: input.mint ?? null, isWritable: false },
    destination: { value: input.destination ?? null, isWritable: true },
    authority: { value: input.authority ?? null, isWritable: false },
  };
  const accounts = originalAccounts as Record<keyof typeof originalAccounts, ResolvedAccount>;

  // Original args.
  const args = { ...input };

  // Remaining accounts.
  const remainingAccounts: AccountMeta[] = (args.multiSigners ?? []).map((signer) => ({
    address: signer.address,
    role: AccountRole.READONLY_SIGNER,
    signer,
  }));

  const getAccountMeta = getAccountMetaFactory(programAddress, 'programId');
  return Object.freeze({
    accounts: [
      getAccountMeta(accounts.source),
      getAccountMeta(accounts.mint),
      getAccountMeta(accounts.destination),
      getAccountMeta(accounts.authority),
      ...remainingAccounts,
    ],
    data: getTransferCheckedInstructionDataEncoder().encode(args as TransferCheckedInstructionDataArgs),
    programAddress,
  } as TransferCheckedInstruction<
    TProgramAddress,
    TAccountSource,
    TAccountMint,
    TAccountDestination,
    (typeof input)['authority'] extends TransactionSigner<TAccountAuthority>
      ? ReadonlySignerAccount<TAccountAuthority> & AccountSignerMeta<TAccountAuthority>
      : TAccountAuthority
  >);
}

export type ParsedTransferCheckedInstruction<
  TProgram extends string = typeof TOKEN_2022_PROGRAM_ADDRESS,
  TAccountMetas extends readonly AccountMeta[] = readonly AccountMeta[],
> = {
  programAddress: Address<TProgram>;
  accounts: {
    /** The source account. */
    source: TAccountMetas[0];
    /** The token mint. */
    mint: TAccountMetas[1];
    /** The destination account. */
    destination: TAccountMetas[2];
    /** The source account's owner/delegate or its multisignature account. */
    authority: TAccountMetas[3];
  };
  data: TransferCheckedInstructionData;
};

export function parseTransferCheckedInstruction<TProgram extends string, TAccountMetas extends readonly AccountMeta[]>(
  instruction: Instruction<TProgram> &
    InstructionWithAccounts<TAccountMetas> &
    InstructionWithData<ReadonlyUint8Array>,
): ParsedTransferCheckedInstruction<TProgram, TAccountMetas> {
  if (instruction.accounts.length < 4) {
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
    accounts: {
      source: getNextAccount(),
      mint: getNextAccount(),
      destination: getNextAccount(),
      authority: getNextAccount(),
    },
    data: getTransferCheckedInstructionDataDecoder().decode(instruction.data),
  };
}
