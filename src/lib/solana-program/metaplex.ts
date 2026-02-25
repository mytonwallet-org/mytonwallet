import type { AccountMeta, Address, Instruction } from '@solana/kit';
import {
  AccountRole,
  fixEncoderSize,
  getAddressEncoder,
  getBase58Encoder,
  getBytesEncoder,
  getOptionEncoder,
  getProgramDerivedAddress,
  getStructEncoder,
  getU8Encoder,
  getU32Encoder,
  getU64Encoder,
  getUtf8Encoder,
} from '@solana/kit';

import { SOLANA_PROGRAM_IDS } from '../../api/chains/solana/constants';

const BUBBLEGUM_PROGRAM_ID = SOLANA_PROGRAM_IDS.nft[2] as Address;
const COMPRESSION_PROGRAM_ID = 'cmtDvXumGCrqC1Age74AVPhSRVXJMd8PJS91L8KbNCK' as Address;
const NOOP_PROGRAM_ID = 'noopb9bkMVfRPU8AsbpTUg8AQkHtKwMYZiFUjNRtMmV' as Address;
const SYSVAR_PROGRAM_ID = 'Sysvar1nstructions1111111111111111111111111' as Address;

const TOKEN_METADATA_PROGRAM_ID = 'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s' as Address;
const MPL_AUTH_RULES_PROGRAM_ID = 'auth9SigNpDKz4sJJ1DfCTuZrZNSAgh9sFD3rboVmgg' as Address;
const DEFAULT_RULE_SET_PROGRAM_ID = 'AdH2Utn6Fus15ZhtenW4hZBQnvtLgM1YCW2MfVp7pYS5' as Address;

async function deriveTreeAuthority(treeAddress: string) {
  const [treePda] = await getProgramDerivedAddress({
    programAddress: BUBBLEGUM_PROGRAM_ID,
    seeds: [getAddressEncoder().encode(treeAddress as Address)],
  });
  return treePda;
}

const transferEncoder = getStructEncoder([
  ['discriminator', fixEncoderSize(getBytesEncoder(), 8)],
  ['root', fixEncoderSize(getBytesEncoder(), 32)],
  ['dataHash', fixEncoderSize(getBytesEncoder(), 32)],
  ['creatorHash', fixEncoderSize(getBytesEncoder(), 32)],
  ['nonce', getU64Encoder()],
  ['index', getU32Encoder()],
]);

export async function transferCNFT(params: {
  tree: string;
  owner: string;
  newOwner: string;
  root: string;
  dataHash: string;
  creatorHash: string;
  index: number;
  proof: string[];
  canopyDepth: number;
}) {
  const treePda = await deriveTreeAuthority(params.tree);

  const base58Encoder = getBase58Encoder();

  const instructionData = transferEncoder.encode({
    discriminator: new Uint8Array([163, 52, 200, 231, 140, 3, 69, 186]),
    root: base58Encoder.encode(params.root),
    dataHash: base58Encoder.encode(params.dataHash),
    creatorHash: base58Encoder.encode(params.creatorHash),
    nonce: BigInt(params.index),
    index: params.index,
  });

  const transferInstruction = {
    programAddress: BUBBLEGUM_PROGRAM_ID,
    accounts: [
      { address: treePda, role: AccountRole.READONLY },
      { address: params.owner as Address, role: AccountRole.WRITABLE_SIGNER },
      { address: params.owner as Address, role: AccountRole.WRITABLE_SIGNER },
      { address: params.newOwner as Address, role: AccountRole.READONLY },
      { address: params.tree as Address, role: AccountRole.WRITABLE },
      { address: NOOP_PROGRAM_ID, role: AccountRole.READONLY },
      { address: COMPRESSION_PROGRAM_ID, role: AccountRole.READONLY },
      { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
      ...params.proof.map((p) => ({ address: p as Address, role: AccountRole.READONLY }))
        .slice(0, params.proof.length - params.canopyDepth),
    ],
    data: instructionData,
  };

  return transferInstruction as Instruction<typeof BUBBLEGUM_PROGRAM_ID>;
}

export function getMplCoreTransferInstruction(
  asset: string,
  sender: string,
  recipient: string,
  collection?: string,
): Instruction {
  const accounts = [
    { address: asset as Address, role: AccountRole.WRITABLE },
    { address: (collection || SOLANA_PROGRAM_IDS.system[0]) as Address, role: AccountRole.READONLY },
    { address: sender as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: sender as Address, role: AccountRole.READONLY },
    { address: recipient as Address, role: AccountRole.READONLY },
    { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
    { address: NOOP_PROGRAM_ID, role: AccountRole.READONLY },
  ];

  const encoder = getStructEncoder([
    ['discriminator', getU8Encoder()],
    ['compressionProof', getOptionEncoder(
      getU8Encoder(),
    )],
  ]);

  const data = encoder.encode({
    discriminator: 14,
    // eslint-disable-next-line no-null/no-null
    compressionProof: null,
  });

  return {
    programAddress: SOLANA_PROGRAM_IDS.nft[1] as Address,
    accounts,
    data,
  };
}

const addrEncoder = getAddressEncoder();

async function findTokenRecordPda(mint: Address, token: Address) {
  return await getProgramDerivedAddress({
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    seeds: [
      getUtf8Encoder().encode('metadata'),
      addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
      addrEncoder.encode(mint),
      getUtf8Encoder().encode('token_record'),
      addrEncoder.encode(token),
    ],
  });
}

export async function getPnftTransferInstruction(input: {
  mint: string;
  source: string;
  sourceToken: string;
  destination: string;
  destinationToken: string;
}): Promise<Instruction> {
  const [metadata] = await getProgramDerivedAddress({
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    seeds: [
      Buffer.from('metadata'),
      addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
      addrEncoder.encode(input.mint as Address),
    ],
  });

  const [edition] = await getProgramDerivedAddress({
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    seeds: [
      Buffer.from('metadata'),
      addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
      addrEncoder.encode(input.mint as Address),
      Buffer.from('edition'),
    ],
  });

  const [ownerTokenRecord] = await findTokenRecordPda(input.mint as Address, input.sourceToken as Address);
  const [destinationTokenRecord] = await findTokenRecordPda(input.mint as Address, input.destinationToken as Address);

  // https://github.com/metaplex-foundation/mpl-token-metadata/blob/main/clients/js/src/generated/instructions/transferV1.ts
  const keys: AccountMeta[] = [
    { address: input.sourceToken as Address, role: AccountRole.WRITABLE },
    { address: input.source as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: input.destinationToken as Address, role: AccountRole.WRITABLE },
    { address: input.destination as Address, role: AccountRole.READONLY },
    { address: input.mint as Address, role: AccountRole.READONLY },
    { address: metadata, role: AccountRole.WRITABLE },
    { address: edition, role: AccountRole.READONLY },
    { address: ownerTokenRecord, role: AccountRole.WRITABLE },
    { address: destinationTokenRecord, role: AccountRole.WRITABLE },
    { address: input.source as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: input.source as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
    { address: SYSVAR_PROGRAM_ID, role: AccountRole.READONLY },
    { address: SOLANA_PROGRAM_IDS.token[0] as Address, role: AccountRole.READONLY },
    { address: SOLANA_PROGRAM_IDS.ata[0] as Address, role: AccountRole.READONLY },
    { address: MPL_AUTH_RULES_PROGRAM_ID, role: AccountRole.READONLY },
    { address: DEFAULT_RULE_SET_PROGRAM_ID, role: AccountRole.READONLY },
  ];

  const data = new Uint8Array([49, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]);

  return {
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    accounts: keys,
    data,
  };
}

export async function burnCNFT(params: {
  tree: string;
  owner: string;
  root: string;
  dataHash: string;
  creatorHash: string;
  index: number;
  proof: string[];
  canopyDepth: number;
}) {
  const treePda = await deriveTreeAuthority(params.tree);

  const encoder = getStructEncoder([
    ['discriminator', fixEncoderSize(getBytesEncoder(), 8)],
    ['root', fixEncoderSize(getBytesEncoder(), 32)],
    ['dataHash', fixEncoderSize(getBytesEncoder(), 32)],
    ['creatorHash', fixEncoderSize(getBytesEncoder(), 32)],
    ['nonce', getU64Encoder()],
    ['index', getU32Encoder()],
  ]);

  const base58Encoder = getBase58Encoder();

  const instructionData = encoder.encode({
    discriminator: new Uint8Array([116, 110, 29, 56, 107, 219, 42, 93]),
    root: base58Encoder.encode(params.root),
    dataHash: base58Encoder.encode(params.dataHash),
    creatorHash: base58Encoder.encode(params.creatorHash),
    nonce: BigInt(params.index),
    index: params.index,
  });

  return {
    programAddress: BUBBLEGUM_PROGRAM_ID,
    accounts: [
      { address: treePda, role: AccountRole.WRITABLE },
      { address: params.owner as Address, role: AccountRole.WRITABLE_SIGNER },
      { address: params.owner as Address, role: AccountRole.WRITABLE_SIGNER },
      { address: params.tree as Address, role: AccountRole.WRITABLE },
      { address: NOOP_PROGRAM_ID, role: AccountRole.READONLY },
      { address: COMPRESSION_PROGRAM_ID, role: AccountRole.READONLY },
      { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
      ...params.proof.map((p) => ({ address: p as Address, role: AccountRole.READONLY }))
        .slice(0, params.proof.length - params.canopyDepth),
    ],
    data: instructionData,
  };
}

export function burnMPLCoreNft(params: { asset: string; owner: string; collection?: string }) {
  const { asset, owner, collection } = params;

  const encoder = getStructEncoder([
    ['discriminator', getU8Encoder()],
    ['compressionProof', getOptionEncoder(
      getU8Encoder(),
    )],
  ]);

  const accounts = [
    { address: asset as Address, role: AccountRole.WRITABLE },
    { address: (collection || SOLANA_PROGRAM_IDS.system[0]) as Address, role: AccountRole.WRITABLE },
    { address: owner as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: owner as Address, role: AccountRole.WRITABLE_SIGNER },
    { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
    { address: NOOP_PROGRAM_ID, role: AccountRole.READONLY },
  ];

  return {
    programAddress: SOLANA_PROGRAM_IDS.nft[1] as Address,
    accounts,
    data: encoder.encode({
      discriminator: 12,
      // eslint-disable-next-line no-null/no-null
      compressionProof: null,
    }),
  };
}

export async function burnLegacyNft(params: {
  mint: string;
  owner: string;
  ownerTokenAccount: string;
  collectionAddress?: string;
}) {
  const [metadata] = await getProgramDerivedAddress({
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    seeds: [
      Buffer.from('metadata'),
      addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
      addrEncoder.encode(params.mint as Address),
    ],
  });

  const [edition] = await getProgramDerivedAddress({
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    seeds: [
      Buffer.from('metadata'),
      addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
      addrEncoder.encode(params.mint as Address),
      Buffer.from('edition'),
    ],
  });

  const [ownerTokenRecord] = await findTokenRecordPda(params.mint as Address, params.ownerTokenAccount as Address);

  let collectionMetadataAddress = '';

  if (params.collectionAddress) {
    const [collectionMetadata] = await getProgramDerivedAddress({
      programAddress: TOKEN_METADATA_PROGRAM_ID,
      seeds: [
        Buffer.from('metadata'),
        addrEncoder.encode(TOKEN_METADATA_PROGRAM_ID),
        addrEncoder.encode(params.collectionAddress as Address),
      ],
    });

    collectionMetadataAddress = collectionMetadata;
  }

  const accounts: AccountMeta[] = [
    { address: params.owner as Address, role: AccountRole.WRITABLE_SIGNER },
    {
      address: (collectionMetadataAddress || TOKEN_METADATA_PROGRAM_ID) as Address,
      role: collectionMetadataAddress ? AccountRole.WRITABLE : AccountRole.READONLY,
    },

    { address: metadata as Address, role: AccountRole.WRITABLE },
    { address: edition as Address, role: AccountRole.WRITABLE },

    { address: params.mint as Address, role: AccountRole.WRITABLE },
    { address: params.ownerTokenAccount as Address, role: AccountRole.WRITABLE },

    { address: TOKEN_METADATA_PROGRAM_ID, role: AccountRole.READONLY },

    { address: TOKEN_METADATA_PROGRAM_ID, role: AccountRole.READONLY },
    { address: TOKEN_METADATA_PROGRAM_ID, role: AccountRole.READONLY },
    { address: TOKEN_METADATA_PROGRAM_ID, role: AccountRole.READONLY },

    { address: ownerTokenRecord, role: AccountRole.WRITABLE },

    { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
    { address: SYSVAR_PROGRAM_ID, role: AccountRole.READONLY },
    { address: SOLANA_PROGRAM_IDS.token[0] as Address, role: AccountRole.READONLY },
  ];

  const legacyBurnEncoder = getStructEncoder([
    ['discriminator', getU8Encoder()],
    ['burnV1Discriminator', getU8Encoder()],
    ['amount', getU64Encoder()],
  ]);

  return {
    programAddress: TOKEN_METADATA_PROGRAM_ID,
    accounts,
    data: legacyBurnEncoder.encode({
      discriminator: 41,
      burnV1Discriminator: 0,
      amount: 1n,
    }),
  };
}
