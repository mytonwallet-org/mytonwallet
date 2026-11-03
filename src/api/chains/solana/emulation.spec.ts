import type { Address, Blockhash, Instruction } from '@solana/kit';
import {
  AccountRole,
  appendTransactionMessageInstructions,
  compileTransaction,
  createTransactionMessage,
  getAddressDecoder,
  getAddressEncoder,
  getBase64EncodedWireTransaction,
  getBase64Encoder,
  getCompiledTransactionMessageDecoder,
  getTransactionDecoder,
  getU32Encoder,
  getU64Encoder,
  pipe,
  setTransactionMessageFeePayer,
  setTransactionMessageLifetimeUsingBlockhash,
} from '@solana/kit';

import type { ApiTransactionActivity } from '../../types';

import { SOLANA, SOLANA_USDC_MAINNET } from '../../../config';
import { getSetComputeUnitLimitInstruction } from '../../../lib/solana-program/computeBudget';
import { getTransferSolInstructionDataEncoder } from '../../../lib/solana-program/system';
import { fetchJson } from '../../../util/fetch';
import { buildTokenSlug, getTokensCache } from '../../common/tokens';
import { DEFAULT_FEE, SOLANA_PROGRAM_IDS, WSOL_MINT } from './constants';
import { parseTransactionForPreview } from './emulation';

jest.mock('../../../util/fetch', () => ({
  fetchJson: jest.fn(),
}));

jest.mock('./util/metadata', () => ({
  updateTokensMetadataByAddress: jest.fn().mockResolvedValue(undefined),
}));

function makeAddress(seed: number) {
  return getAddressDecoder().decode(new Uint8Array(32).fill(seed));
}

const USER = makeAddress(1);
const ATTACKER = makeAddress(2);
const DECOY = makeAddress(3);
const USER_TOKEN_ACCOUNT = makeAddress(4);
const ATTACKER_TOKEN_ACCOUNT = makeAddress(5);
const MINT = makeAddress(6);
const BLOCKHASH = makeAddress(7) as string as Blockhash;
const USER_WRAPPED_SOL_ACCOUNT = makeAddress(8);
const ATTACKER_WRAPPED_SOL_ACCOUNT = makeAddress(9);
const USER_JUNK_ACCOUNT = makeAddress(10);
const ATTACKER_JUNK_ACCOUNT = makeAddress(11);
const JUNK_MINT = makeAddress(12);

const LAMPORTS_PER_SOL = 1_000_000_000n;

function transferSol(destination: Address, amount: bigint): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
    accounts: [
      { address: USER, role: AccountRole.WRITABLE_SIGNER },
      { address: destination, role: AccountRole.WRITABLE },
    ],
    data: getTransferSolInstructionDataEncoder().encode({ amount }),
  };
}

function transferToken(source = USER_TOKEN_ACCOUNT, destination = ATTACKER_TOKEN_ACCOUNT, amount = 100n): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
    accounts: [
      { address: source, role: AccountRole.WRITABLE },
      { address: destination, role: AccountRole.WRITABLE },
      { address: USER, role: AccountRole.READONLY_SIGNER },
    ],
    data: new Uint8Array([3, ...getU64Encoder().encode(amount)]),
  };
}

function closeUserTokenAccount(account: Address, refundTo: Address): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
    accounts: [
      { address: account, role: AccountRole.WRITABLE },
      { address: refundTo, role: AccountRole.WRITABLE },
      { address: USER, role: AccountRole.READONLY_SIGNER },
    ],
    data: new Uint8Array([9]),
  };
}

function openAttackerTokenAccount(payer: Address): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.ata[0] as Address,
    accounts: [
      { address: payer, role: AccountRole.WRITABLE_SIGNER },
      { address: ATTACKER_TOKEN_ACCOUNT, role: AccountRole.WRITABLE },
      { address: ATTACKER, role: AccountRole.READONLY },
      { address: MINT, role: AccountRole.READONLY },
      { address: SOLANA_PROGRAM_IDS.system[0] as Address, role: AccountRole.READONLY },
      { address: SOLANA_PROGRAM_IDS.token[0] as Address, role: AccountRole.READONLY },
    ],
    data: new Uint8Array([1]),
  };
}

function closeAttackerTokenAccount(refundTo: Address): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
    accounts: [
      { address: ATTACKER_TOKEN_ACCOUNT, role: AccountRole.WRITABLE },
      { address: refundTo, role: AccountRole.WRITABLE },
      { address: ATTACKER, role: AccountRole.READONLY_SIGNER },
    ],
    data: new Uint8Array([9]),
  };
}

function setUserTokenAccountOwner(account: Address, newOwner: Address): Instruction {
  const ACCOUNT_OWNER_AUTHORITY = 2;

  return {
    programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
    accounts: [
      { address: account, role: AccountRole.WRITABLE },
      { address: USER, role: AccountRole.READONLY_SIGNER },
    ],
    data: new Uint8Array([6, ACCOUNT_OWNER_AUTHORITY, 1, ...getAddressEncoder().encode(newOwner)]),
  };
}

function getAccountKeys(rawTx: string) {
  const { messageBytes } = getTransactionDecoder().decode(getBase64Encoder().encode(rawTx));
  return getCompiledTransactionMessageDecoder().decode(messageBytes).staticAccounts as readonly string[];
}

function buildRawTx(instructions: Instruction[]) {
  const message = pipe(
    createTransactionMessage({ version: 0 }),
    (m) => setTransactionMessageFeePayer(USER, m),
    (m) => setTransactionMessageLifetimeUsingBlockhash({ blockhash: BLOCKHASH, lastValidBlockHeight: 0n }, m),
    (m) => appendTransactionMessageInstructions(instructions, m),
  );

  return getBase64EncodedWireTransaction(compileTransaction(message));
}

function getTransactionActivities(emulation: Awaited<ReturnType<typeof parseTransactionForPreview>>['emulation']) {
  return (emulation?.activities ?? []) as ApiTransactionActivity[];
}

function getApprovalSimulation(addresses: readonly string[], delegate?: Address) {
  return { result: { value: {
    // eslint-disable-next-line no-null/no-null
    err: null,
    accounts: addresses.map(() => ({ data: { parsed: { type: 'account', info: delegate ? { delegate } : {} } } })),
  } } };
}

function mockTokenTransfer(rawTx: string, innerInstructions: object[] | undefined, mint: string = MINT) {
  const keys = getAccountKeys(rawTx);
  const response = {
    result: {
      value: {
        ...(innerInstructions === undefined ? {} : { innerInstructions }),
        fee: 5000,
        preBalances: keys.map((key) => (key === USER ? Number(LAMPORTS_PER_SOL) : 0)),
        postBalances: keys.map((key) => (key === USER ? Number(LAMPORTS_PER_SOL) - 5000 : 0)),
        preTokenBalances: [
          { accountIndex: keys.indexOf(USER_TOKEN_ACCOUNT), mint, owner: USER,
            uiTokenAmount: { amount: '1000' } },
          { accountIndex: keys.indexOf(ATTACKER_TOKEN_ACCOUNT), mint, owner: ATTACKER,
            uiTokenAmount: { amount: '0' } },
        ],
        postTokenBalances: [
          { accountIndex: keys.indexOf(USER_TOKEN_ACCOUNT), mint, owner: USER,
            uiTokenAmount: { amount: '900' } },
          { accountIndex: keys.indexOf(ATTACKER_TOKEN_ACCOUNT), mint, owner: ATTACKER,
            uiTokenAmount: { amount: '100' } },
        ],
      },
    },
  };
  jest.mocked(fetchJson).mockImplementation((_url, _returnError, options) => {
    const { method, params } = JSON.parse(options!.body as string);
    if (method !== 'simulateTransaction') throw new Error(`Unexpected RPC method: ${method}`);
    if (params[1].accounts) {
      return Promise.resolve(getApprovalSimulation(params[1].accounts.addresses, ATTACKER));
    }
    return Promise.resolve(response);
  });
  return response.result.value;
}

describe('parseTransactionForPreview', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it.each([false, true])('shows all SOL transfers (Memo and ComputeBudget: %s)', async (hasMetadataInstructions) => {
    const instructions = [
      transferSol(ATTACKER, 10n * LAMPORTS_PER_SOL),
      transferSol(DECOY, 1n),
    ];
    if (hasMetadataInstructions) {
      instructions.push({
        programAddress: SOLANA_PROGRAM_IDS.memo[0] as Address,
        data: new Uint8Array(Buffer.from('Payment')),
      }, {
        programAddress: SOLANA_PROGRAM_IDS.computeBudget[0] as Address,
        data: new Uint8Array([2, ...getU32Encoder().encode(200_000)]),
      });
    }
    const rawTx = buildRawTx(instructions);

    const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');
    const activities = getTransactionActivities(emulation);

    expect(fetchJson).not.toHaveBeenCalled();
    expect(transfers.every((transfer) => !transfer.isDangerous)).toBe(true);
    expect(activities).toHaveLength(2);
    expect(activities[0]).toMatchObject({
      toAddress: ATTACKER,
      amount: -10n * LAMPORTS_PER_SOL,
      slug: SOLANA.slug,
    });
    expect(activities[1]).toMatchObject({
      toAddress: DECOY,
      amount: -1n,
      slug: SOLANA.slug,
    });
    expect(new Set(activities.map(({ id }) => id)).size).toBe(activities.length);
    if (hasMetadataInstructions) {
      expect(activities[0].comment).toBe('Payment');
    }
  });

  it('shows a SOL transfer with a priority fee and no token balances', async () => {
    const amount = 1000n;
    const fee = 10_000_005_001;
    const startBalance = 20 * Number(LAMPORTS_PER_SOL);
    const rawTx = buildRawTx([
      transferSol(ATTACKER, amount),
      getSetComputeUnitLimitInstruction(1_400_000),
      {
        programAddress: SOLANA_PROGRAM_IDS.computeBudget[0] as Address,
        data: new Uint8Array([3, ...getU64Encoder().encode(7_142_857_143n)]),
      },
    ]);
    const keys = getAccountKeys(rawTx);
    const preBalances = keys.map((key) => (key === USER ? startBalance : 0));
    const postBalances = preBalances.map((balance, index) => {
      if (keys[index] === USER) return balance - fee - Number(amount);
      return keys[index] === ATTACKER ? balance + Number(amount) : balance;
    });

    jest.mocked(fetchJson).mockResolvedValue({
      result: {
        value: { innerInstructions: [], fee, preBalances, postBalances,
          preTokenBalances: [], postTokenBalances: [] },
      },
    });

    const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

    expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: false })]);
    expect(getTransactionActivities(emulation)).toEqual([expect.objectContaining({
      fromAddress: USER,
      toAddress: ATTACKER,
      amount: -amount,
      slug: SOLANA.slug,
      fee: BigInt(fee),
    })]);
    expect(emulation?.networkFee).toBe(BigInt(fee));
    expect(emulation?.realFee).toBe(BigInt(fee));
    expect(fetchJson).toHaveBeenCalledTimes(1);
  });

  it.each([
    {
      name: 'omits the priority fee',
      mockSimulation: () => jest.mocked(fetchJson).mockResolvedValue({
        result: { value: { preTokenBalances: [], postTokenBalances: [] } },
      }),
    },
    {
      name: 'returns a JSON-RPC error',
      mockSimulation: () => jest.mocked(fetchJson).mockResolvedValue({
        error: { code: -32005, message: 'Node is behind' },
      }),
    },
    {
      name: 'fails',
      mockSimulation: () => jest.mocked(fetchJson).mockRejectedValue(new Error('Network error')),
    },
  ])('warns when the simulation $name', async ({ mockSimulation }) => {
    const rawTx = buildRawTx([
      transferSol(ATTACKER, 1000n),
      getSetComputeUnitLimitInstruction(1_400_000),
      {
        programAddress: SOLANA_PROGRAM_IDS.computeBudget[0] as Address,
        data: new Uint8Array([3, ...getU64Encoder().encode(7_142_857_143n)]),
      },
    ]);
    mockSimulation();

    const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

    expect(fetchJson).toHaveBeenCalledTimes(1);
    expect(emulation).toBeUndefined();
    expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
  });

  it.each([
    {
      name: 'zero compute unit price',
      instruction: {
        programAddress: SOLANA_PROGRAM_IDS.computeBudget[0] as Address,
        data: new Uint8Array([3, ...getU64Encoder().encode(0n)]),
      },
    },
    { name: 'compute unit limit', instruction: getSetComputeUnitLimitInstruction(1_400_000) },
  ])('keeps a SOL transfer with $name on the simple path', async ({ instruction }) => {
    const rawTx = buildRawTx([transferSol(ATTACKER, 1000n), instruction]);

    const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

    expect(fetchJson).not.toHaveBeenCalled();
    expect(emulation?.networkFee).toBe(DEFAULT_FEE);
    expect(emulation?.realFee).toBe(DEFAULT_FEE);
  });

  it.each([
    { name: 'empty data', data: new Uint8Array() },
    { name: 'truncated price', data: new Uint8Array([3]) },
  ])('simulates a SOL transfer with unparseable ComputeBudget $name', async ({ data }) => {
    const rawTx = buildRawTx([
      transferSol(ATTACKER, 1000n),
      { programAddress: SOLANA_PROGRAM_IDS.computeBudget[0] as Address, data },
    ]);
    jest.mocked(fetchJson).mockResolvedValue({
      result: {
        value: {
          innerInstructions: [],
          fee: 5000,
          preBalances: [Number(LAMPORTS_PER_SOL)],
          postBalances: [Number(LAMPORTS_PER_SOL) - 5000],
          preTokenBalances: [],
          postTokenBalances: [],
        },
      },
    });

    const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

    expect(fetchJson).toHaveBeenCalledTimes(1);
    expect(emulation).toBeUndefined();
    expect(transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
  });

  describe('System instructions requiring simulation', () => {
    beforeEach(() => {
      jest.mocked(fetchJson).mockResolvedValue({
        result: {
          value: {
            innerInstructions: [],
            fee: 5000,
            preBalances: [Number(LAMPORTS_PER_SOL)],
            postBalances: [Number(LAMPORTS_PER_SOL) - 5000],
            preTokenBalances: [],
            postTokenBalances: [],
          },
        },
      });
    });

    describe.each([false, true])('alongside TransferSol: %s', (hasSolTransfer) => {
      it.each([
        { name: 'CreateAccount', discriminator: 0, dataLength: 52, accountCount: 2 },
        { name: 'Assign', discriminator: 1, dataLength: 36, accountCount: 1 },
        { name: 'CreateAccountWithSeed', discriminator: 3, dataLength: 92, accountCount: 3 },
        { name: 'AdvanceNonceAccount', discriminator: 4, dataLength: 4, accountCount: 3 },
        { name: 'WithdrawNonceAccount', discriminator: 5, dataLength: 12, accountCount: 5 },
        { name: 'AuthorizeNonceAccount', discriminator: 7, dataLength: 36, accountCount: 2 },
        { name: 'AssignWithSeed', discriminator: 10, dataLength: 76, accountCount: 2 },
        { name: 'TransferSolWithSeed', discriminator: 11, dataLength: 52, accountCount: 3 },
      ])('simulates $name and warns when no user token changes are found', async ({
        discriminator, dataLength, accountCount,
      }) => {
        const data = new Uint8Array(dataLength);
        data.set(getU32Encoder().encode(discriminator));
        const instruction: Instruction = {
          programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
          accounts: [USER, ATTACKER, DECOY, USER_TOKEN_ACCOUNT, ATTACKER_TOKEN_ACCOUNT]
            .slice(0, accountCount)
            .map((address, index) => ({
              address,
              role: index === 0 ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
            })),
          data,
        };
        const rawTx = buildRawTx(hasSolTransfer
          ? [transferSol(ATTACKER, LAMPORTS_PER_SOL), instruction]
          : [instruction]);

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(fetchJson).toHaveBeenCalledTimes(1);
        expect(JSON.parse(jest.mocked(fetchJson).mock.calls[0][2]!.body as string)).toMatchObject({
          method: 'simulateTransaction',
          params: [rawTx, expect.any(Object)],
        });
        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });
    });

    it.each([
      { name: 'empty data', dataLength: 0, accountCount: 2 },
      { name: 'truncated data', dataLength: 11, accountCount: 2 },
      { name: 'trailing data', dataLength: 13, accountCount: 2 },
      { name: 'one account', dataLength: 12, accountCount: 1 },
    ])('simulates TransferSol with $name and warns when no user token changes are found', async ({
      dataLength, accountCount,
    }) => {
      const transfer = transferSol(ATTACKER, LAMPORTS_PER_SOL);
      const data = new Uint8Array(dataLength);
      data.set(transfer.data!.slice(0, dataLength));
      const rawTx = buildRawTx([{ ...transfer, data, accounts: transfer.accounts!.slice(0, accountCount) }]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(fetchJson).toHaveBeenCalledTimes(1);
      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });
  });

  describe('System account changes alongside a visible token transfer', () => {
    const unknownProgram = makeAddress(13);
    const recentBlockhashes = 'SysvarRecentB1ockHashes11111111111111111111' as Address;
    const rentSysvar = 'SysvarRent111111111111111111111111111111111' as Address;
    const unknownInstruction: Instruction = {
      programAddress: unknownProgram,
      accounts: [
        ...[USER, DECOY, ATTACKER, USER_TOKEN_ACCOUNT, ATTACKER_TOKEN_ACCOUNT, ATTACKER_JUNK_ACCOUNT]
          .map((address) => ({
            address,
            role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
          })),
        ...[recentBlockhashes, rentSysvar, SOLANA_PROGRAM_IDS.system[0] as Address].map((address) => ({
          address, role: AccountRole.READONLY,
        })),
      ],
      data: new Uint8Array([1]),
    };
    const accountChanges = [
      {
        name: 'Assign',
        discriminator: 1,
        accounts: [USER],
        data: getAddressEncoder().encode(ATTACKER),
        type: 'assign',
        info: { account: USER, owner: unknownProgram },
      },
      {
        name: 'AuthorizeNonceAccount',
        discriminator: 7,
        accounts: [DECOY, USER],
        data: getAddressEncoder().encode(ATTACKER),
        type: 'authorizeNonce',
        info: { nonceAccount: DECOY, nonceAuthority: USER, newAuthorized: ATTACKER },
      },
      {
        name: 'WithdrawNonceAccount',
        discriminator: 5,
        accounts: [DECOY, ATTACKER, recentBlockhashes, rentSysvar, USER],
        data: getU64Encoder().encode(LAMPORTS_PER_SOL),
        type: 'withdrawFromNonce',
        info: { nonceAccount: DECOY, nonceAuthority: USER, destination: ATTACKER, lamports: Number(LAMPORTS_PER_SOL) },
      },
      {
        name: 'Allocate',
        discriminator: 8,
        accounts: [USER],
        data: getU64Encoder().encode(80),
        type: 'allocate',
        info: { account: USER, space: 80 },
      },
      {
        name: 'AllocateWithSeed',
        discriminator: 9,
        accounts: [DECOY, USER],
        data: new Uint8Array([
          ...getAddressEncoder().encode(USER),
          ...getU64Encoder().encode(4), ...Buffer.from('seed'),
          ...getU64Encoder().encode(80), ...getAddressEncoder().encode(ATTACKER),
        ]),
        type: 'allocateWithSeed',
        info: { account: DECOY, base: USER, seed: 'seed', space: 80, owner: ATTACKER },
      },
      {
        name: 'AssignWithSeed',
        discriminator: 10,
        accounts: [DECOY, USER],
        data: new Uint8Array([
          ...getAddressEncoder().encode(USER),
          ...getU64Encoder().encode(4), ...Buffer.from('seed'),
          ...getAddressEncoder().encode(ATTACKER),
        ]),
        type: 'assignWithSeed',
        info: { account: DECOY, base: USER, seed: 'seed', owner: ATTACKER },
      },
      {
        name: 'TransferSolWithSeed',
        discriminator: 11,
        accounts: [DECOY, USER, ATTACKER],
        data: new Uint8Array([
          ...getU64Encoder().encode(LAMPORTS_PER_SOL),
          ...getU64Encoder().encode(4), ...Buffer.from('seed'),
          ...getAddressEncoder().encode(SOLANA_PROGRAM_IDS.system[0] as Address),
        ]),
        type: 'transferWithSeed',
        info: { source: DECOY, sourceBase: USER, destination: ATTACKER, lamports: Number(LAMPORTS_PER_SOL) },
      },
    ];

    it.each(accountChanges)('warns about top-level $name', async ({ discriminator, accounts, data }) => {
      const rawTx = buildRawTx([transferToken(), {
        programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
        accounts: accounts.map((address) => ({
          address,
          role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
        })),
        data: new Uint8Array([...getU32Encoder().encode(discriminator), ...data]),
      }]);
      mockTokenTransfer(rawTx, []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each(accountChanges)('warns about $name through CPI', async ({ type, info }) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [{ parsed: { type, info }, program: 'system',
          programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each([false, true])('warns about creating an account at the user address (CPI: %s)', async (isCpi) => {
      const creation: Instruction = {
        programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
        accounts: [ATTACKER, USER].map((address) => ({ address, role: AccountRole.WRITABLE_SIGNER })),
        data: new Uint8Array([
          ...getU32Encoder().encode(0), ...getU64Encoder().encode(LAMPORTS_PER_SOL),
          ...getU64Encoder().encode(80), ...getAddressEncoder().encode(ATTACKER),
        ]),
      };
      const rawTx = buildRawTx([transferToken(), isCpi ? unknownInstruction : creation]);
      mockTokenTransfer(rawTx, isCpi ? [{
        index: 1,
        instructions: [{ parsed: { type: 'createAccount', info: { source: ATTACKER, newAccount: USER,
          lamports: Number(LAMPORTS_PER_SOL), space: 80, owner: ATTACKER } },
        program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }] : []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    describe.each([false, true])('SOL forwarded through the user (CPI: %s)', (isCpi) => {
      it.each(accountChanges.filter(({ type }) => type === 'withdrawFromNonce' || type === 'transferWithSeed'))(
        'warns about $name forwarded through the user',
        async ({ discriminator, accounts, data, type, info }) => {
          const withdrawal: Instruction = {
            programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
            accounts: accounts.map((address) => ({
              address: address === ATTACKER ? USER : address,
              role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
            })),
            data: new Uint8Array([...getU32Encoder().encode(discriminator), ...data]),
          };
          const rawTx = buildRawTx(isCpi
            ? [transferToken(), unknownInstruction]
            : [transferToken(), withdrawal, transferSol(ATTACKER, LAMPORTS_PER_SOL)]);
          mockTokenTransfer(rawTx, isCpi ? [{
            index: 1,
            instructions: [
              { parsed: { type, info: { ...info, destination: USER } },
                program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
              { parsed: { type: 'transfer', info: { source: USER, destination: ATTACKER,
                lamports: Number(LAMPORTS_PER_SOL) } },
              program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
            ],
          }] : []);

          const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

          expect(emulation).toBeUndefined();
          expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
        },
      );
    });

    it('warns about a nonce withdrawal signed by the user at the destination position', async () => {
      const rawTx = buildRawTx([transferToken(), {
        programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
        accounts: [DECOY, USER, recentBlockhashes, rentSysvar, ATTACKER_JUNK_ACCOUNT].map((address) => ({
          address,
          role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
        })),
        data: new Uint8Array([...getU32Encoder().encode(5), ...getU64Encoder().encode(LAMPORTS_PER_SOL)]),
      }, transferSol(ATTACKER, LAMPORTS_PER_SOL)]);
      mockTokenTransfer(rawTx, []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each([
      { type: 'authorizeNonce', info: { nonceAccount: DECOY, nonceAuthority: ATTACKER_JUNK_ACCOUNT,
        newAuthorized: ATTACKER } },
      { type: 'withdrawFromNonce', info: { nonceAccount: DECOY, nonceAuthority: ATTACKER_JUNK_ACCOUNT,
        destination: USER, lamports: Number(LAMPORTS_PER_SOL) } },
    ])('warns about $type through CPI with an authority outside the parsed position', async ({ type, info }) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [
          { parsed: { type, info }, program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
          ...(type === 'withdrawFromNonce' ? [{
            parsed: { type: 'transfer', info: { source: USER, destination: ATTACKER,
              lamports: Number(LAMPORTS_PER_SOL) } },
            program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2,
          }] : []),
        ],
      }]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('warns about a nonce withdrawal through CPI without the user in parsed info', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [{ parsed: { type: 'withdrawFromNonce', info: { nonceAccount: DECOY,
          nonceAuthority: ATTACKER, destination: ATTACKER_JUNK_ACCOUNT, lamports: Number(LAMPORTS_PER_SOL) } },
        program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each([false, true])('warns about initialization of the user\'s own nonce account (CPI: %s)', async (isCpi) => {
      const rawTx = buildRawTx([transferToken(), isCpi ? unknownInstruction : {
        programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
        accounts: [USER, recentBlockhashes, rentSysvar].map((address) => ({
          address,
          role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.READONLY,
        })),
        data: new Uint8Array([...getU32Encoder().encode(6), ...getAddressEncoder().encode(ATTACKER)]),
      }]);
      mockTokenTransfer(rawTx, isCpi ? [{
        index: 1,
        instructions: [{ parsed: { type: 'initializeNonce', info: { nonceAccount: USER, nonceAuthority: ATTACKER } },
          program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }] : []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('preserves the token transfer preview with a prefunded ATA allocated and assigned through CPI', async () => {
      const rawTx = buildRawTx([openAttackerTokenAccount(USER), transferToken()]);
      const rent = 1600200;
      const prefunded = 1;
      const topUp = rent - prefunded;
      const simulation = mockTokenTransfer(rawTx, [{
        index: 0,
        instructions: [
          { parsed: { type: 'transfer', info: { source: USER, destination: ATTACKER_TOKEN_ACCOUNT, lamports: topUp } },
            program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
          { parsed: { type: 'allocate', info: { account: ATTACKER_TOKEN_ACCOUNT, space: 165 } },
            program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
          { parsed: { type: 'assign', info: { account: ATTACKER_TOKEN_ACCOUNT, owner: SOLANA_PROGRAM_IDS.token[0] } },
            program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
        ],
      }]);
      const keys = getAccountKeys(rawTx);
      simulation.preBalances[keys.indexOf(ATTACKER_TOKEN_ACCOUNT)] = prefunded;
      simulation.postBalances[keys.indexOf(ATTACKER_TOKEN_ACCOUNT)] = rent;
      simulation.postBalances[keys.indexOf(USER)] -= topUp;
      simulation.preTokenBalances = simulation.preTokenBalances.filter(({ owner }) => owner === USER);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual({
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 1605199n, received: 0n, traceOutputs: [], realFee: 1605199n,
          activities: [{ id: '0', kind: 'transaction', timestamp: 0, comment: undefined,
            fromAddress: USER, toAddress: ATTACKER, amount: -100n, slug: buildTokenSlug('solana', MINT),
            isIncoming: false, normalizedAddress: ATTACKER, fee: 5000n, status: 'completed', metadata: {} }],
        },
      });
    });

    it('preserves the token transfer preview with initialization of another nonce account through CPI', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [{ parsed: { type: 'initializeNonce', info: { nonceAccount: DECOY, nonceAuthority: USER } },
          program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }]);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual({
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 5000n, received: 0n, traceOutputs: [], realFee: 5000n,
          activities: [{ id: '0', kind: 'transaction', timestamp: 0, comment: undefined,
            fromAddress: USER, toAddress: ATTACKER, amount: -100n, slug: buildTokenSlug('solana', MINT),
            isIncoming: false, normalizedAddress: ATTACKER, fee: 5000n, status: 'completed', metadata: {} }],
        },
      });
    });

    it('warns about an unparsed System CPI involving the user', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [{ accounts: [DECOY, USER], data: '1',
          programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('warns when simulation omits innerInstructions for an unknown program', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockTokenTransfer(rawTx, undefined);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('preserves the swap preview with System funding CPI and AdvanceNonceAccount', async () => {
      const rawTx = buildRawTx([unknownInstruction, {
        programAddress: SOLANA_PROGRAM_IDS.system[0] as Address,
        accounts: [DECOY, recentBlockhashes, USER].map((address) => ({
          address,
          role: address === USER ? AccountRole.READONLY_SIGNER : AccountRole.WRITABLE,
        })),
        data: getU32Encoder().encode(4),
      }]);
      const keys = getAccountKeys(rawTx);
      const rent = 1600200;
      jest.mocked(fetchJson).mockResolvedValue({
        result: {
          value: {
            fee: 5000,
            preBalances: keys.map((key) => (key === USER ? Number(3n * LAMPORTS_PER_SOL) : 0)),
            postBalances: keys.map((key) => (key === USER ? Number(2n * LAMPORTS_PER_SOL) - 5000 : 0)),
            preTokenBalances: [{
              accountIndex: keys.indexOf(USER_TOKEN_ACCOUNT), mint: SOLANA_USDC_MAINNET.tokenAddress,
              owner: USER, uiTokenAmount: { amount: '0' } }],
            postTokenBalances: [{
              accountIndex: keys.indexOf(USER_TOKEN_ACCOUNT), mint: SOLANA_USDC_MAINNET.tokenAddress,
              owner: USER, uiTokenAmount: { amount: '100000000' } }],
            innerInstructions: [{
              index: 0,
              instructions: [
                { parsed: { type: 'transfer', info: { source: USER, destination: ATTACKER,
                  lamports: Number(LAMPORTS_PER_SOL) - rent } },
                program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
                { parsed: { type: 'createAccount', info: { source: USER, newAccount: ATTACKER_JUNK_ACCOUNT,
                  lamports: rent, space: 0, owner: unknownProgram } },
                program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 3 },
              ],
            }],
          },
        },
      });

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual({
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 5000n, received: 0n, traceOutputs: [], realFee: 5000n,
          activities: [{ id: '', kind: 'swap', fromAddress: USER, timestamp: 0,
            from: SOLANA.slug, fromAmount: '1', to: SOLANA_USDC_MAINNET.slug, toAmount: '100',
            networkFee: '5000', swapFee: '0', status: 'completed', hashes: [], transactionIds: {} }],
        },
      });
    });

    it('preserves the token transfer preview with a seeded transfer from another base to the user', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      const simulation = mockTokenTransfer(rawTx, [{
        index: 1,
        instructions: [{ parsed: { type: 'transferWithSeed', info: { source: DECOY,
          sourceBase: ATTACKER, destination: USER, lamports: Number(LAMPORTS_PER_SOL) } },
        program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 }],
      }], SOLANA_USDC_MAINNET.tokenAddress);
      simulation.postBalances[getAccountKeys(rawTx).indexOf(USER)] += Number(LAMPORTS_PER_SOL);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual({
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 5000n, received: 0n, traceOutputs: [], realFee: 5000n,
          activities: [{ id: '', kind: 'swap', fromAddress: USER, timestamp: 0,
            from: SOLANA_USDC_MAINNET.slug, fromAmount: '0.0001', to: SOLANA.slug, toAmount: '1',
            networkFee: '5000', swapFee: '0', status: 'completed', hashes: [], transactionIds: {} }],
        },
      });
    });
  });

  describe('Token and stake authority changes alongside a visible token transfer', () => {
    const stakeProgram = 'Stake11111111111111111111111111111111111111';
    const stakeAccount = makeAddress(14);
    const emptyTokenAccount = makeAddress(15);
    const tokenMint = SOLANA_USDC_MAINNET.tokenAddress as Address;
    const unknownInstruction: Instruction = {
      programAddress: makeAddress(13),
      accounts: [USER, USER_TOKEN_ACCOUNT, ATTACKER_TOKEN_ACCOUNT, stakeAccount, USER_WRAPPED_SOL_ACCOUNT]
        .map((address) => ({
          address, role: address === USER ? AccountRole.WRITABLE_SIGNER : AccountRole.WRITABLE,
        })),
      data: new Uint8Array([1]),
    };

    function tokenInstruction(discriminator: number, accounts: Address[], authorityType = 3): Instruction {
      return {
        programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
        accounts: accounts.map((address) => ({
          address, role: address === USER ? AccountRole.READONLY_SIGNER : AccountRole.WRITABLE,
        })),
        data: discriminator === 6
          ? new Uint8Array([6, authorityType, 1, ...getAddressEncoder().encode(ATTACKER)])
          : new Uint8Array([discriminator, ...getU64Encoder().encode(100n),
            ...([12, 13, 14].includes(discriminator) ? [6] : [])]),
      };
    }

    function stakeInstruction(discriminator: number, accounts = [stakeAccount, ATTACKER, USER]): Instruction {
      return {
        programAddress: stakeProgram as Address,
        accounts: accounts.map((address) => ({
          address, role: address === USER ? AccountRole.READONLY_SIGNER : AccountRole.WRITABLE,
        })),
        data: getU32Encoder().encode(discriminator),
      };
    }

    function tokenCpi(type: string, info: object) {
      return { parsed: { type, info }, program: 'spl-token', programId: SOLANA_PROGRAM_IDS.token[0], stackHeight: 2 };
    }

    function stakeCpi(type: string, info: object) {
      return { parsed: { type, info }, program: 'stake', programId: stakeProgram, stackHeight: 2 };
    }

    function mockCpi(rawTx: string, instructions: object[], {
      staker = ATTACKER, withdrawer = USER, custodian = SOLANA_PROGRAM_IDS.system[0] as Address, lookup, approvalLookup,
    }: {
      staker?: Address;
      withdrawer?: Address;
      custodian?: Address;
      lookup?: (addresses: string[]) => Record<string, unknown>;
      approvalLookup?: (addresses: string[]) => Record<string, unknown>;
    } = {}) {
      const simulation = mockTokenTransfer(rawTx, [{ index: 1, instructions }], SOLANA_USDC_MAINNET.tokenAddress);
      jest.mocked(fetchJson).mockImplementation((_url, _returnError, options) => {
        const { method, params } = JSON.parse(options!.body as string);
        if (method === 'simulateTransaction') {
          const addresses = params[1].accounts?.addresses;
          if (addresses) {
            const result = approvalLookup ? approvalLookup(addresses) : getApprovalSimulation(addresses, ATTACKER);
            return Promise.resolve(result);
          }
          return Promise.resolve({ result: { value: simulation } });
        }
        if (method !== 'getMultipleAccounts') throw new Error(`Unexpected RPC method: ${method}`);
        if (lookup) return Promise.resolve(lookup(params[0]));
        return Promise.resolve({ result: { value: params[0].map((address: string) => (address === stakeAccount ? {
          owner: stakeProgram,
          data: { parsed: { type: 'delegated', info: { meta: {
            authorized: { staker, withdrawer },
            lockup: { custodian, epoch: 0, unixTimestamp: 0 },
            rentExemptReserve: '2282880',
          } } } },
        } : { owner: SOLANA_PROGRAM_IDS.system[0], data: [] })) } });
      });
      return simulation;
    }

    function expectedTokenPreview(rawTx: string, isIncoming = false) {
      return {
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 5000n, received: 0n, traceOutputs: [], realFee: 5000n,
          activities: [{ id: '0', kind: 'transaction', timestamp: 0, comment: undefined,
            fromAddress: isIncoming ? ATTACKER : USER, toAddress: isIncoming ? USER : ATTACKER,
            amount: isIncoming ? 100n : -100n, slug: SOLANA_USDC_MAINNET.slug,
            isIncoming, normalizedAddress: ATTACKER, fee: 5000n, status: 'completed', metadata: {} }],
        },
      };
    }

    function expectedSwapPreview(rawTx: string, from: string = SOLANA_USDC_MAINNET.slug, fromAmount = '0.0001') {
      return {
        transfers: [{ chain: 'solana', toAddress: '', amount: 0n, rawPayload: rawTx, isDangerous: false,
          normalizedAddress: '', displayedToAddress: '', networkFee: 0n }],
        emulation: {
          networkFee: 5000n, received: 0n, traceOutputs: [], realFee: 5000n,
          activities: [{ id: '', kind: 'swap', fromAddress: USER, timestamp: 0,
            from, fromAmount, to: SOLANA.slug, toAmount: '1',
            networkFee: '5000', swapFee: '0', status: 'completed', hashes: [], transactionIds: {} }],
        },
      };
    }

    it.each([false, true])('preserves a delegate-consumed approval (CPI: %s)', async (isCpi) => {
      const delegatedTransfer = { ...transferToken(), accounts: [
        ...transferToken().accounts!.slice(0, 2),
        { address: ATTACKER, role: AccountRole.READONLY_SIGNER },
      ] };
      const rawTx = buildRawTx(isCpi ? [unknownInstruction] : [
        tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, USER]), delegatedTransfer,
      ]);
      mockCpi(rawTx, isCpi ? [
        tokenCpi('approve', { source: USER_TOKEN_ACCOUNT, delegate: ATTACKER, owner: USER, amount: '100' }),
        tokenCpi('transferChecked', { source: USER_TOKEN_ACCOUNT, destination: ATTACKER_TOKEN_ACCOUNT,
          mint: SOLANA_USDC_MAINNET.tokenAddress, authority: ATTACKER, tokenAmount: { amount: '100' } }),
      ] : [], { approvalLookup: getApprovalSimulation });

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
    });

    it('preserves a token transfer when an approval is revoked in the transaction', async () => {
      const rawTx = buildRawTx([
        tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, USER]), transferToken(),
        { ...tokenInstruction(5, [USER_TOKEN_ACCOUNT, USER]), data: new Uint8Array([5]) },
      ]);
      mockCpi(rawTx, [], { approvalLookup: getApprovalSimulation });

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
    });

    it('warns about an approval whose delegate remains after the transaction', async () => {
      const rawTx = buildRawTx([
        tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, USER]), transferToken(),
      ]);
      mockCpi(rawTx, []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      expect(fetchJson).toHaveBeenCalledTimes(2);
      expect(JSON.parse(jest.mocked(fetchJson).mock.calls[1][2]!.body as string)).toEqual({
        jsonrpc: '2.0', id: '1', method: 'simulateTransaction',
        params: [rawTx, { encoding: 'base64', replaceRecentBlockhash: true, innerInstructions: true,
          accounts: { addresses: [USER_TOKEN_ACCOUNT], encoding: 'jsonParsed' } }],
      });
    });

    it.each([
      { name: 'omits accounts', approvalLookup: () => ({ result: { value: {
        err: getApprovalSimulation([]).result.value.err,
      } } }) },
      { name: 'returns a transaction error', approvalLookup: (addresses: string[]) => ({
        result: { value: { ...getApprovalSimulation(addresses).result.value,
          err: { InstructionError: [0, 'InvalidArgument'] } } },
      }) },
      { name: 'throws', approvalLookup: () => { throw new Error('Approval simulation unavailable'); } },
      ...[
        { name: 'omits token account info', parsed: { type: 'account' } },
        // eslint-disable-next-line no-null/no-null
        { name: 'returns a null delegate', parsed: { type: 'account', info: { delegate: null } } },
        { name: 'returns a numeric delegate', parsed: { type: 'account', info: { delegate: 0 } } },
      ].map(({ name, parsed }) => ({ name, approvalLookup: (addresses: string[]) => ({ result: { value: {
        ...getApprovalSimulation(addresses).result.value,
        accounts: addresses.map(() => ({ data: { parsed } })),
      } } }) })),
    ])('warns when the approval simulation $name', async ({ approvalLookup }) => {
      const rawTx = buildRawTx([
        tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, USER]), transferToken(),
      ]);
      mockCpi(rawTx, [], { approvalLookup });

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      expect(fetchJson).toHaveBeenCalledTimes(2);
    });

    it.each([false, true])('preserves renouncing mint authority (CPI: %s)', async (isCpi) => {
      const rawTx = buildRawTx([transferToken(), isCpi ? unknownInstruction : {
        ...tokenInstruction(6, [MINT, USER], 0), data: new Uint8Array([6, 0, 0]),
      }]);
      const inner = tokenCpi('setAuthority', { account: MINT, authority: USER, authorityType: 'mintTokens',
        // eslint-disable-next-line no-null/no-null
        newAuthority: null });
      mockCpi(rawTx, isCpi ? [inner] : []);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
      expect(fetchJson).toHaveBeenCalledTimes(1);
    });

    describe.each([false, true])('additional token authorities (CPI: %s)', (isCpi) => {
      it.each([
        { type: 'closeAccount', discriminator: 9, accounts: [emptyTokenAccount, ATTACKER, USER],
          info: { account: emptyTokenAccount, destination: ATTACKER, owner: USER },
          programId: SOLANA_PROGRAM_IDS.token[0] },
        { type: 'withdrawExcessLamports', discriminator: 38, accounts: [USER_TOKEN_ACCOUNT, ATTACKER, USER],
          info: { source: USER_TOKEN_ACCOUNT, destination: ATTACKER, authority: USER },
          programId: SOLANA_PROGRAM_IDS.token[1] },
        { type: 'mintTo', discriminator: 7, accounts: [tokenMint, ATTACKER_TOKEN_ACCOUNT, USER],
          info: { mint: tokenMint, account: ATTACKER_TOKEN_ACCOUNT, mintAuthority: USER },
          programId: SOLANA_PROGRAM_IDS.token[0] },
        { type: 'mintToChecked', discriminator: 14, accounts: [tokenMint, ATTACKER_TOKEN_ACCOUNT, USER],
          info: { mint: tokenMint, account: ATTACKER_TOKEN_ACCOUNT, mintAuthority: USER },
          programId: SOLANA_PROGRAM_IDS.token[0] },
        { type: 'freezeAccount', discriminator: 10, accounts: [USER_TOKEN_ACCOUNT, tokenMint, USER],
          info: { account: USER_TOKEN_ACCOUNT, mint: tokenMint, freezeAuthority: USER },
          programId: SOLANA_PROGRAM_IDS.token[0] },
      ])('warns about $type using the user authority outside shown holdings', async ({
        type, discriminator, accounts, info, programId,
      }) => {
        const instruction = tokenInstruction(discriminator, accounts);
        const rawTx = buildRawTx([transferToken(), isCpi ? unknownInstruction : {
          ...instruction, programAddress: programId as Address,
          data: [9, 10, 38].includes(discriminator) ? new Uint8Array([discriminator]) : instruction.data,
        }]);
        const simulation = mockCpi(rawTx, isCpi ? [{ ...tokenCpi(type, info), programId }] : []);
        if (type === 'mintTo' || type === 'mintToChecked') simulation.postTokenBalances[1].uiTokenAmount.amount = '200';

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });

      it.each([
        { type: 'mintTo', discriminator: 7, remaining: 0n },
        { type: 'mintTo', discriminator: 7, remaining: 1n },
        { type: 'mintToChecked', discriminator: 14, remaining: 0n },
        { type: 'mintToChecked', discriminator: 14, remaining: 1n },
      ])('warns about $type forwarded to an attacker with $remaining tokens left', async ({
        type, discriminator, remaining,
      }) => {
        const forwarded = 100n - remaining;
        const outer = { ...unknownInstruction, accounts: [
          ...unknownInstruction.accounts!,
          ...[JUNK_MINT, USER_JUNK_ACCOUNT, ATTACKER_JUNK_ACCOUNT]
            .map((address) => ({ address, role: AccountRole.WRITABLE })),
        ] };
        const rawTx = buildRawTx([transferToken(), ...(isCpi ? [outer] : [
          tokenInstruction(discriminator, [JUNK_MINT, USER_JUNK_ACCOUNT, USER]),
          transferToken(USER_JUNK_ACCOUNT, ATTACKER_JUNK_ACCOUNT, forwarded),
        ])]);
        const simulation = mockCpi(rawTx, isCpi ? [
          tokenCpi(type, { mint: JUNK_MINT, account: USER_JUNK_ACCOUNT, mintAuthority: USER,
            ...(type === 'mintTo' ? { amount: '100' } : { tokenAmount: { amount: '100' } }) }),
          tokenCpi('transfer', { source: USER_JUNK_ACCOUNT, destination: ATTACKER_JUNK_ACCOUNT,
            authority: USER, amount: forwarded.toString() }),
        ] : []);
        const keys = getAccountKeys(rawTx);
        simulation.preTokenBalances.push(
          { accountIndex: keys.indexOf(USER_JUNK_ACCOUNT), mint: JUNK_MINT, owner: USER,
            uiTokenAmount: { amount: '0' } },
          { accountIndex: keys.indexOf(ATTACKER_JUNK_ACCOUNT), mint: JUNK_MINT, owner: ATTACKER,
            uiTokenAmount: { amount: '0' } },
        );
        simulation.postTokenBalances.push(
          { accountIndex: keys.indexOf(USER_JUNK_ACCOUNT), mint: JUNK_MINT, owner: USER,
            uiTokenAmount: { amount: remaining.toString() } },
          { accountIndex: keys.indexOf(ATTACKER_JUNK_ACCOUNT), mint: JUNK_MINT, owner: ATTACKER,
            uiTokenAmount: { amount: forwarded.toString() } },
        );

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });

      it('warns about renouncing close authority over an account owned by another user', async () => {
        const outer = { ...unknownInstruction, accounts: [
          ...unknownInstruction.accounts!,
          { address: ATTACKER_WRAPPED_SOL_ACCOUNT, role: AccountRole.WRITABLE },
        ] };
        const rawTx = buildRawTx([transferToken(), isCpi ? outer : {
          ...tokenInstruction(6, [ATTACKER_WRAPPED_SOL_ACCOUNT, USER], 3), data: new Uint8Array([6, 3, 0]),
        }]);
        const inner = tokenCpi('setAuthority', { account: ATTACKER_WRAPPED_SOL_ACCOUNT, authority: USER,
          // eslint-disable-next-line no-null/no-null
          authorityType: 'closeAccount', newAuthority: null });
        const simulation = mockCpi(rawTx, isCpi ? [inner] : []);
        const accountIndex = getAccountKeys(rawTx).indexOf(ATTACKER_WRAPPED_SOL_ACCOUNT);
        simulation.preBalances[accountIndex] = 2039280 + Number(2n * LAMPORTS_PER_SOL);
        simulation.postBalances[accountIndex] = simulation.preBalances[accountIndex];
        const balance = { accountIndex, mint: WSOL_MINT, owner: ATTACKER,
          uiTokenAmount: { amount: (2n * LAMPORTS_PER_SOL).toString() } };
        simulation.preTokenBalances.push(balance);
        simulation.postTokenBalances.push(balance);

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });

      it('preserves minting tokens to the user account', async () => {
        const rawTx = buildRawTx([unknownInstruction, ...(isCpi ? [] : [
          tokenInstruction(7, [tokenMint, USER_TOKEN_ACCOUNT, USER]),
        ])]);
        const simulation = mockCpi(rawTx, isCpi ? [tokenCpi('mintTo', {
          mint: tokenMint, account: USER_TOKEN_ACCOUNT, mintAuthority: USER, amount: '100',
        })] : []);
        simulation.postTokenBalances[0].uiTokenAmount.amount = '1100';
        simulation.postTokenBalances[1].uiTokenAmount.amount = '0';

        const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(result).toEqual(expectedTokenPreview(rawTx, true));
        expect(fetchJson).toHaveBeenCalledTimes(1);
      });
    });

    describe.each(SOLANA_PROGRAM_IDS.token)('top-level token program %s', (programId) => {
      it.each([
        { name: 'Approve', instruction: tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, USER]) },
        { name: 'ApproveChecked', instruction: tokenInstruction(13, [USER_TOKEN_ACCOUNT, MINT, ATTACKER, USER]) },
        { name: 'SetAuthority CloseAccount', instruction: tokenInstruction(6, [USER_TOKEN_ACCOUNT, USER], 3) },
        { name: 'SetAuthority MintTokens', instruction: tokenInstruction(6, [MINT, USER], 0) },
        { name: 'SetAuthority AccountOwner on an empty account',
          instruction: tokenInstruction(6, [emptyTokenAccount, USER], 2) },
        { name: 'Approve with the user as a multisig signer',
          instruction: tokenInstruction(4, [USER_TOKEN_ACCOUNT, ATTACKER, DECOY, USER]) },
      ])('warns about $name', async ({ instruction }) => {
        const rawTx = buildRawTx([transferToken(), { ...instruction, programAddress: programId as Address }]);
        const simulation = mockTokenTransfer(rawTx, []);
        simulation.preTokenBalances.push({ accountIndex: getAccountKeys(rawTx).indexOf(emptyTokenAccount),
          mint: MINT, owner: USER, uiTokenAmount: { amount: '0' } });

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
        if ([4, 13].includes(instruction.data![0])) expect(fetchJson).toHaveBeenCalledTimes(2);
      });
    });

    describe.each([false, true])('token ownership after a transfer (CPI: %s)', (isCpi) => {
      it.each([0n, 1n])('warns when the account changes owner with %s tokens left', async (remaining) => {
        const amount = 1000n - remaining;
        const rawTx = buildRawTx(isCpi ? [unknownInstruction] : [
          transferToken(USER_TOKEN_ACCOUNT, ATTACKER_TOKEN_ACCOUNT, amount),
          setUserTokenAccountOwner(USER_TOKEN_ACCOUNT, ATTACKER),
        ]);
        const simulation = mockCpi(rawTx, isCpi ? [
          tokenCpi('transferChecked', { source: USER_TOKEN_ACCOUNT, mint: SOLANA_USDC_MAINNET.tokenAddress,
            destination: ATTACKER_TOKEN_ACCOUNT, authority: USER, tokenAmount: { amount: amount.toString() } }),
          tokenCpi('setAuthority', { account: USER_TOKEN_ACCOUNT, authority: USER,
            authorityType: 'accountOwner', newAuthority: ATTACKER }),
        ] : []);
        simulation.postTokenBalances[0].owner = ATTACKER;
        simulation.postTokenBalances[0].uiTokenAmount.amount = remaining.toString();
        simulation.postTokenBalances[1].uiTokenAmount.amount = amount.toString();

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });
    });

    it.each([
      { type: 'approve', info: { source: USER_TOKEN_ACCOUNT, delegate: ATTACKER, owner: USER } },
      { type: 'approveChecked', info: { source: USER_TOKEN_ACCOUNT, mint: MINT, delegate: ATTACKER, owner: USER } },
      { type: 'setAuthority', info: { account: USER_TOKEN_ACCOUNT, authority: USER,
        authorityType: 'closeAccount', newAuthority: ATTACKER } },
      { type: 'approve', info: { source: USER_TOKEN_ACCOUNT, delegate: ATTACKER,
        multisigOwner: DECOY, signers: [ATTACKER, USER] } },
    ])('warns about parsed token $type with $info', async ({ type, info }) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [tokenCpi(type, info)]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each([SOLANA_PROGRAM_IDS.token[0], stakeProgram])('warns about unparsed %s CPI involving the user',
      async (programId) => {
        const rawTx = buildRawTx([transferToken(), unknownInstruction]);
        mockCpi(rawTx, [{ programId, accounts: [stakeAccount, USER], data: '1', stackHeight: 2 }]);

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });

    it.each([
      { name: 'Authorize', discriminator: 1 },
      { name: 'AuthorizeChecked', discriminator: 10 },
      { name: 'AuthorizeWithSeed', discriminator: 8 },
      { name: 'AuthorizeCheckedWithSeed', discriminator: 11 },
      { name: 'SetLockup', discriminator: 6 },
      { name: 'SetLockupChecked', discriminator: 12 },
      { name: 'Split', discriminator: 3 },
      { name: 'Merge', discriminator: 7 },
    ])('warns about top-level $name with the user as an extra account at the end', async ({ discriminator }) => {
      const rawTx = buildRawTx([transferToken(), stakeInstruction(discriminator,
        [stakeAccount, ATTACKER, DECOY, USER])]);
      mockTokenTransfer(rawTx, []);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it.each([ATTACKER, USER])('warns about stake Withdraw to %s, including SOL forwarded through the user',
      async (destination) => {
        const rawTx = buildRawTx([transferToken(), stakeInstruction(4, [stakeAccount, destination, DECOY, USER]),
          ...(destination === USER ? [transferSol(ATTACKER, LAMPORTS_PER_SOL)] : [])]);
        mockTokenTransfer(rawTx, []);

        const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(emulation).toBeUndefined();
        expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      });

    it.each([
      { type: 'authorize', info: { stakeAccount, authority: ATTACKER, newAuthority: DECOY }, staker: USER,
        withdrawer: ATTACKER },
      { type: 'setLockup', info: { stakeAccount, custodian: ATTACKER }, staker: ATTACKER, withdrawer: USER },
      { type: 'split', info: { stakeAccount, newSplitAccount: DECOY, authority: ATTACKER },
        staker: ATTACKER, withdrawer: USER },
      { type: 'withdraw', info: { stakeAccount, destination: USER, withdrawAuthority: ATTACKER,
        lamports: Number(LAMPORTS_PER_SOL) }, staker: ATTACKER, withdrawer: USER },
    ])('warns about parsed stake $type based on the account state', async ({ type, info, staker, withdrawer }) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [stakeCpi(type, info), ...(type === 'withdraw' ? [{
        parsed: { type: 'transfer', info: { source: USER, destination: ATTACKER,
          lamports: Number(LAMPORTS_PER_SOL) } },
        program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2,
      }] : [])], { staker, withdrawer });

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      expect(fetchJson).toHaveBeenCalledTimes(2);
      expect(JSON.parse(jest.mocked(fetchJson).mock.calls[1][2]!.body as string)).toMatchObject({
        method: 'getMultipleAccounts', params: [expect.arrayContaining([stakeAccount]), { encoding: 'jsonParsed' }],
      });
    });

    it('warns about parsed setLockup based on the user custodian in account state', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [stakeCpi('setLockup', { stakeAccount, custodian: ATTACKER })], {
        staker: ATTACKER, withdrawer: ATTACKER, custodian: USER,
      });

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('warns about authorizeWithSeed using the user as authorityBase without an account lookup', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [stakeCpi('authorizeWithSeed', { stakeAccount, authorityBase: USER, newAuthority: ATTACKER })]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      expect(fetchJson).toHaveBeenCalledTimes(1);
    });

    it.each([
      { name: 'rejects', lookup: () => { throw new Error('RPC unavailable'); } },
      { name: 'returns an error', lookup: (addresses: string[]) => ({
        error: { code: -32603, message: 'RPC unavailable' },
        result: { value: addresses.map(() => ({
          owner: stakeProgram,
          data: { parsed: { type: 'delegated', info: { meta: {
            authorized: { staker: ATTACKER, withdrawer: ATTACKER },
            lockup: { custodian: SOLANA_PROGRAM_IDS.system[0], epoch: 0, unixTimestamp: 0 },
            rentExemptReserve: '2282880',
          } } } },
        })) },
      }) },
      { name: 'returns the wrong number of accounts', lookup: () => ({ result: { value: [] } }) },
      { name: 'returns accounts without an owner', lookup: (addresses: string[]) => ({
        result: { value: addresses.map(() => ({})) },
      }) },
      { name: 'returns stake accounts without lockup', lookup: (addresses: string[]) => ({
        result: { value: addresses.map(() => ({
          owner: stakeProgram,
          data: { parsed: { type: 'delegated', info: { meta: {
            authorized: { staker: ATTACKER, withdrawer: ATTACKER },
            rentExemptReserve: '2282880',
          } } } },
        })) },
      }) },
    ])('warns when the stake account lookup $name', async ({ lookup }) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [stakeCpi('authorize', { stakeAccount, authority: ATTACKER, newAuthority: DECOY })], { lookup });

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('preserves an SPL transferChecked with idempotent ATA creation and token initialization CPI', async () => {
      const rawTx = buildRawTx([
        tokenInstruction(12, [USER_TOKEN_ACCOUNT, MINT, ATTACKER_TOKEN_ACCOUNT, USER]),
        openAttackerTokenAccount(USER),
      ]);
      mockCpi(rawTx, [
        tokenCpi('getAccountDataSize', { mint: MINT, extensionTypes: ['immutableOwner'] }),
        { parsed: { type: 'createAccount', info: { source: USER, newAccount: ATTACKER_TOKEN_ACCOUNT,
          lamports: 2039280, space: 165, owner: SOLANA_PROGRAM_IDS.token[0] } },
        program: 'system', programId: SOLANA_PROGRAM_IDS.system[0], stackHeight: 2 },
        tokenCpi('initializeImmutableOwner', { account: ATTACKER_TOKEN_ACCOUNT }),
        tokenCpi('initializeAccount3', { account: ATTACKER_TOKEN_ACCOUNT, mint: MINT, owner: ATTACKER }),
      ]);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
      expect(fetchJson).toHaveBeenCalledTimes(1);
    });

    it('preserves an ordinary swap with token transfer, wrapped SOL initialization, sync and close CPI', async () => {
      const rawTx = buildRawTx([unknownInstruction]);
      const simulation = mockCpi(rawTx, [
        tokenCpi('transferChecked', { source: USER_TOKEN_ACCOUNT, mint: SOLANA_USDC_MAINNET.tokenAddress,
          destination: ATTACKER_TOKEN_ACCOUNT, authority: USER, tokenAmount: { amount: '100' } }),
        tokenCpi('syncNative', { account: USER_WRAPPED_SOL_ACCOUNT }),
        tokenCpi('initializeAccount3', { account: USER_WRAPPED_SOL_ACCOUNT, mint: WSOL_MINT, owner: USER }),
        tokenCpi('closeAccount', { account: USER_WRAPPED_SOL_ACCOUNT, destination: USER, owner: USER }),
      ]);
      simulation.postBalances[getAccountKeys(rawTx).indexOf(USER)] += Number(LAMPORTS_PER_SOL);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedSwapPreview(rawTx));
      expect(fetchJson).toHaveBeenCalledTimes(1);
    });

    it('preserves an LST to SOL swap withdrawing from a pool reserve owned by another authority', async () => {
      const lstSlug = buildTokenSlug('solana', MINT);
      const tokens = getTokensCache().bySlug;
      tokens[lstSlug] = { ...SOLANA_USDC_MAINNET, slug: lstSlug, tokenAddress: MINT,
        name: 'Liquid staking token', symbol: 'LST', decimals: 9, priceUsd: 0, percentChange24h: 0 };
      try {
        const rawTx = buildRawTx([unknownInstruction]);
        const simulation = mockCpi(rawTx, [stakeCpi('withdraw', { stakeAccount, destination: USER,
          withdrawAuthority: ATTACKER, lamports: Number(LAMPORTS_PER_SOL) })], { withdrawer: ATTACKER });
        for (const balance of [...simulation.preTokenBalances, ...simulation.postTokenBalances]) balance.mint = MINT;
        simulation.preTokenBalances[0].uiTokenAmount.amount = '1000000000';
        simulation.postTokenBalances[0].uiTokenAmount.amount = '0';
        simulation.postTokenBalances[1].uiTokenAmount.amount = '1000000000';
        simulation.postBalances[getAccountKeys(rawTx).indexOf(USER)] += Number(LAMPORTS_PER_SOL);

        const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');
        expect(result).toEqual(expectedSwapPreview(rawTx, lstSlug, '1'));
      } finally {
        delete tokens[lstSlug];
      }
    });

    it('preserves stake authorize and split CPI on accounts absent before the transaction', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [
        stakeCpi('authorize', { stakeAccount, authority: ATTACKER, newAuthority: DECOY }),
        stakeCpi('split', { stakeAccount, newSplitAccount: DECOY, authority: ATTACKER }),
      // eslint-disable-next-line no-null/no-null
      ], { lookup: (addresses) => ({ result: { value: addresses.map(() => null) } }) });

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
    });

    it.each(['delegate', 'deactivate'])('preserves parsed stake %s CPI on a user account', async (type) => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, [stakeCpi(type, { stakeAccount, stakeAuthority: USER })]);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
      expect(jest.mocked(fetchJson).mock.calls.map(([, , options]) => JSON.parse(options!.body as string).method))
        .toEqual(['simulateTransaction']);
    });

    it('warns about parsed stake CPI mentioning more than 100 addresses without an account lookup', async () => {
      const rawTx = buildRawTx([transferToken(), unknownInstruction]);
      mockCpi(rawTx, Array.from({ length: 101 }, (_, index) => stakeCpi('authorize', {
        stakeAccount: makeAddress(index + 20), authority: ATTACKER,
      })));

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
      expect(jest.mocked(fetchJson).mock.calls.map(([, , options]) => JSON.parse(options!.body as string).method))
        .toEqual(['simulateTransaction']);
    });

    it.each([{ name: 'DelegateStake', discriminator: 2 }, { name: 'Deactivate', discriminator: 5 }])(
      'preserves top-level $name with the user alongside a token transfer', async ({ discriminator }) => {
        const rawTx = buildRawTx([transferToken(), stakeInstruction(discriminator)]);
        mockTokenTransfer(rawTx, [], SOLANA_USDC_MAINNET.tokenAddress);

        const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

        expect(result).toEqual(expectedTokenPreview(rawTx));
      },
    );

    it.each([
      { name: 'Revoke by the user', instruction: tokenInstruction(5, [USER_TOKEN_ACCOUNT, USER]) },
      { name: 'Approve with the user only as delegate',
        instruction: tokenInstruction(4, [ATTACKER_TOKEN_ACCOUNT, USER, ATTACKER]) },
    ])('preserves $name alongside a token transfer', async ({ instruction }) => {
      const rawTx = buildRawTx([transferToken(), instruction]);
      mockTokenTransfer(rawTx, [], SOLANA_USDC_MAINNET.tokenAddress);

      const result = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(result).toEqual(expectedTokenPreview(rawTx));
    });
  });

  it('passes a transaction with several SOL transfers to signing once', async () => {
    const rawTx = buildRawTx([
      transferSol(ATTACKER, 10n * LAMPORTS_PER_SOL),
      transferSol(DECOY, 1n),
    ]);

    const { transfers } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

    // Signing signs every transfer's raw payload, so a second transfer would put an extra signed copy into a batch
    expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: false })]);
  });

  it('shows both the token and the SOL sent by one transaction', async () => {
    const rawTx = buildRawTx([
      transferSol(ATTACKER, 10n * LAMPORTS_PER_SOL),
      transferToken(),
    ]);
    const fee = 5000;
    const startBalance = 20 * Number(LAMPORTS_PER_SOL);

    jest.mocked(fetchJson).mockResolvedValue({
      result: {
        value: {
          innerInstructions: [],
          fee,
          preBalances: [startBalance],
          postBalances: [startBalance - 10 * Number(LAMPORTS_PER_SOL) - fee],
          preTokenBalances: [
            { accountIndex: 1, mint: MINT, owner: USER, uiTokenAmount: { amount: '1000' } },
            { accountIndex: 2, mint: MINT, owner: ATTACKER, uiTokenAmount: { amount: '0' } },
          ],
          postTokenBalances: [
            { accountIndex: 1, mint: MINT, owner: USER, uiTokenAmount: { amount: '900' } },
            { accountIndex: 2, mint: MINT, owner: ATTACKER, uiTokenAmount: { amount: '100' } },
          ],
        },
      },
    });

    const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');
    const activities = getTransactionActivities(emulation);

    expect(activities).toHaveLength(2);
    expect(activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ slug: buildTokenSlug('solana', MINT), amount: -100n }),
      expect.objectContaining({ slug: SOLANA.slug, amount: -10n * LAMPORTS_PER_SOL }),
    ]));
    expect(emulation?.realFee).toBe(BigInt(fee));
    expect(new Set(activities.map(({ id }) => id)).size).toBe(activities.length);
  });

  describe('rent of the token account a transfer opens', () => {
    const fee = 5000;
    const rent = 1600200;
    const startBalance = Number(LAMPORTS_PER_SOL);

    function mockOpenedAccount(
      rawTx: string,
      { payer, userSpent, fundings = [{ index: 0, source: payer }] }: {
        payer: Address;
        userSpent: number;
        fundings?: { index: number; source: Address }[];
      },
    ) {
      const keys = getAccountKeys(rawTx);
      const userIndex = keys.indexOf(USER);
      const userTokenIndex = keys.indexOf(USER_TOKEN_ACCOUNT);
      const openedIndex = keys.indexOf(ATTACKER_TOKEN_ACCOUNT);
      const preBalances = keys.map((key) => (key === USER ? startBalance : 0));
      const postBalances = preBalances.map((balance, index) => {
        if (index === userIndex) return startBalance - fee - userSpent;
        return index === openedIndex ? rent : balance;
      });

      jest.mocked(fetchJson).mockResolvedValue({
        result: {
          value: {
            fee,
            preBalances,
            postBalances,
            preTokenBalances: [
              { accountIndex: userTokenIndex, mint: MINT, owner: USER, uiTokenAmount: { amount: '1000' } },
            ],
            postTokenBalances: [
              { accountIndex: userTokenIndex, mint: MINT, owner: USER, uiTokenAmount: { amount: '900' } },
              { accountIndex: openedIndex, mint: MINT, owner: ATTACKER, uiTokenAmount: { amount: '100' } },
            ],
            innerInstructions: fundings.map(({ index, source }) => ({
              index,
              instructions: [{
                parsed: {
                  type: 'createAccount',
                  info: { source, newAccount: ATTACKER_TOKEN_ACCOUNT, lamports: rent, space: 187 },
                },
                program: 'system',
                programId: SOLANA_PROGRAM_IDS.system[0],
                stackHeight: 2,
              }],
            })),
          },
        },
      });
    }

    it('shows it in the fee when the user opens the account', async () => {
      const rawTx = buildRawTx([openAttackerTokenAccount(USER), transferToken()]);
      mockOpenedAccount(rawTx, { payer: USER, userSpent: rent });

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual([
        expect.objectContaining({ slug: buildTokenSlug('solana', MINT), amount: -100n }),
      ]);
      expect(emulation?.realFee).toBe(BigInt(fee + rent));
    });

    it('keeps SOL the user sends as a transfer when the dapp opens the account', async () => {
      const rawTx = buildRawTx([
        openAttackerTokenAccount(ATTACKER),
        transferToken(),
        transferSol(ATTACKER, BigInt(rent)),
      ]);
      mockOpenedAccount(rawTx, { payer: ATTACKER, userSpent: rent });

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual(expect.arrayContaining([
        expect.objectContaining({ slug: buildTokenSlug('solana', MINT), amount: -100n }),
        expect.objectContaining({ slug: SOLANA.slug, amount: -BigInt(rent) }),
      ]));
      expect(emulation?.realFee).toBe(BigInt(fee));
    });

    it('keeps SOL as a transfer when the account the user opened is closed and reopened by the dapp', async () => {
      const rawTx = buildRawTx([
        openAttackerTokenAccount(USER),
        closeAttackerTokenAccount(USER),
        openAttackerTokenAccount(ATTACKER),
        transferToken(),
        transferSol(ATTACKER, BigInt(rent)),
      ]);
      mockOpenedAccount(rawTx, {
        payer: USER,
        userSpent: rent,
        fundings: [{ index: 0, source: USER }, { index: 2, source: ATTACKER }],
      });

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual(expect.arrayContaining([
        expect.objectContaining({ slug: buildTokenSlug('solana', MINT), amount: -100n }),
        expect.objectContaining({ slug: SOLANA.slug, amount: -BigInt(rent) }),
      ]));
      expect(emulation?.realFee).toBe(BigInt(fee));
    });
  });

  describe('wrapped SOL of the user', () => {
    const fee = 5000n;
    const rent = 2039280n;
    const wrapped = 2n * LAMPORTS_PER_SOL;
    const WRAPPED_SOL_SLUG = buildTokenSlug('solana', WSOL_MINT);

    function mockSimulation(
      rawTx: string,
      lamports: [Address, bigint, bigint][],
      tokens: { account: Address; owner: Address; mint: string; pre?: bigint; post?: bigint }[],
    ) {
      const keys = getAccountKeys(rawTx);
      const balances = (side: 1 | 2) => keys.map((key) => (
        Number(lamports.find(([address]) => address === key)?.[side] ?? 0)
      ));
      const tokenBalances = (side: 'pre' | 'post') => tokens
        .filter((token) => token[side] !== undefined)
        .map(({ account, owner, mint, [side]: amount }) => ({
          accountIndex: keys.indexOf(account), mint, owner, uiTokenAmount: { amount: String(amount) },
        }));

      jest.mocked(fetchJson).mockResolvedValue({
        result: {
          value: {
            innerInstructions: [],
            fee: Number(fee),
            preBalances: balances(1),
            postBalances: balances(2),
            preTokenBalances: tokenBalances('pre'),
            postTokenBalances: tokenBalances('post'),
          },
        },
      });
    }

    it('shows wrapped SOL the dapp takes from the user', async () => {
      const rawTx = buildRawTx([transferToken(USER_WRAPPED_SOL_ACCOUNT, ATTACKER_WRAPPED_SOL_ACCOUNT, wrapped)]);
      mockSimulation(rawTx, [
        [USER, LAMPORTS_PER_SOL, LAMPORTS_PER_SOL - fee],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped, rent],
        [ATTACKER_WRAPPED_SOL_ACCOUNT, rent, rent + wrapped],
      ], [
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped, post: 0n },
        { account: ATTACKER_WRAPPED_SOL_ACCOUNT, owner: ATTACKER, mint: WSOL_MINT, pre: 0n, post: wrapped },
      ]);

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual([
        expect.objectContaining({ slug: WRAPPED_SOL_SLUG, amount: -wrapped, toAddress: ATTACKER }),
      ]);
    });

    it('shows SOL and wrapped SOL the dapp takes as separate rows', async () => {
      const rawTx = buildRawTx([
        transferSol(ATTACKER, LAMPORTS_PER_SOL),
        transferToken(USER_WRAPPED_SOL_ACCOUNT, ATTACKER_WRAPPED_SOL_ACCOUNT, wrapped),
      ]);
      mockSimulation(rawTx, [
        [USER, 3n * LAMPORTS_PER_SOL, 2n * LAMPORTS_PER_SOL - fee],
        [ATTACKER, 0n, LAMPORTS_PER_SOL],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped, rent],
        [ATTACKER_WRAPPED_SOL_ACCOUNT, rent, rent + wrapped],
      ], [
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped, post: 0n },
        { account: ATTACKER_WRAPPED_SOL_ACCOUNT, owner: ATTACKER, mint: WSOL_MINT, pre: 0n, post: wrapped },
      ]);

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual([
        expect.objectContaining({ slug: SOLANA.slug, amount: -LAMPORTS_PER_SOL, toAddress: ATTACKER }),
        expect.objectContaining({ slug: WRAPPED_SOL_SLUG, amount: -wrapped, toAddress: ATTACKER }),
      ]);
    });

    it('keeps one SOL row when the dapp takes part of the wrapped SOL and unwraps the rest to the user', async () => {
      const rawTx = buildRawTx([
        transferToken(USER_WRAPPED_SOL_ACCOUNT, ATTACKER_WRAPPED_SOL_ACCOUNT, wrapped),
        closeUserTokenAccount(USER_WRAPPED_SOL_ACCOUNT, USER),
      ]);
      mockSimulation(rawTx, [
        [USER, LAMPORTS_PER_SOL, 2n * LAMPORTS_PER_SOL + rent - fee],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped + LAMPORTS_PER_SOL, 0n],
        [ATTACKER_WRAPPED_SOL_ACCOUNT, rent, rent + wrapped],
      ], [
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped + LAMPORTS_PER_SOL },
        { account: ATTACKER_WRAPPED_SOL_ACCOUNT, owner: ATTACKER, mint: WSOL_MINT, pre: 0n, post: wrapped },
      ]);

      const { emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(getTransactionActivities(emulation)).toEqual([
        expect.objectContaining({ slug: SOLANA.slug, amount: -(wrapped - rent) }),
      ]);
    });

    it('warns about wrapped SOL of an account the dapp closes to itself next to a token the user sends', async () => {
      const rawTx = buildRawTx([transferToken(), closeUserTokenAccount(USER_WRAPPED_SOL_ACCOUNT, ATTACKER)]);
      mockSimulation(rawTx, [
        [USER, LAMPORTS_PER_SOL, LAMPORTS_PER_SOL - fee],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped, 0n],
        [ATTACKER, 0n, rent + wrapped],
      ], [
        { account: USER_TOKEN_ACCOUNT, owner: USER, mint: MINT, pre: 1000n, post: 900n },
        { account: ATTACKER_TOKEN_ACCOUNT, owner: ATTACKER, mint: MINT, pre: 0n, post: 100n },
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped },
      ]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });

    it('warns about a swap that takes wrapped SOL next to a token for a token of the dapp', async () => {
      const rawTx = buildRawTx([
        transferToken(),
        transferToken(USER_WRAPPED_SOL_ACCOUNT, ATTACKER_WRAPPED_SOL_ACCOUNT, wrapped),
        transferToken(ATTACKER_JUNK_ACCOUNT, USER_JUNK_ACCOUNT, 1n),
      ]);
      mockSimulation(rawTx, [
        [USER, LAMPORTS_PER_SOL, LAMPORTS_PER_SOL - fee],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped, rent],
        [ATTACKER_WRAPPED_SOL_ACCOUNT, rent, rent + wrapped],
      ], [
        { account: USER_TOKEN_ACCOUNT, owner: USER, mint: MINT, pre: 1000n, post: 900n },
        { account: ATTACKER_TOKEN_ACCOUNT, owner: ATTACKER, mint: MINT, pre: 0n, post: 100n },
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped, post: 0n },
        { account: ATTACKER_WRAPPED_SOL_ACCOUNT, owner: ATTACKER, mint: WSOL_MINT, pre: 0n, post: wrapped },
        { account: ATTACKER_JUNK_ACCOUNT, owner: ATTACKER, mint: JUNK_MINT, pre: 1n, post: 0n },
        { account: USER_JUNK_ACCOUNT, owner: USER, mint: JUNK_MINT, pre: 0n, post: 1n },
      ]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ isDangerous: true })]);
    });

    it('warns about wrapped SOL of an account the dapp becomes the owner of', async () => {
      const rawTx = buildRawTx([setUserTokenAccountOwner(USER_WRAPPED_SOL_ACCOUNT, ATTACKER)]);
      mockSimulation(rawTx, [
        [USER, LAMPORTS_PER_SOL, LAMPORTS_PER_SOL - fee],
        [USER_WRAPPED_SOL_ACCOUNT, rent + wrapped, rent + wrapped],
      ], [
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: USER, mint: WSOL_MINT, pre: wrapped },
        { account: USER_WRAPPED_SOL_ACCOUNT, owner: ATTACKER, mint: WSOL_MINT, post: wrapped },
      ]);

      const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');

      expect(emulation).toBeUndefined();
      expect(transfers).toEqual([expect.objectContaining({ rawPayload: rawTx, isDangerous: true })]);
    });
  });
});
