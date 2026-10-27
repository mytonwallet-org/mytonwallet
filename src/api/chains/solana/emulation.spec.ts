import type { Address, Blockhash, Instruction } from '@solana/kit';
import {
  AccountRole,
  appendTransactionMessageInstructions,
  compileTransaction,
  createTransactionMessage,
  getAddressDecoder,
  getBase64EncodedWireTransaction,
  getBase64Encoder,
  getCompiledTransactionMessageDecoder,
  getTransactionDecoder,
  pipe,
  setTransactionMessageFeePayer,
  setTransactionMessageLifetimeUsingBlockhash,
} from '@solana/kit';

import type { ApiTransactionActivity } from '../../types';

import { SOLANA } from '../../../config';
import { getTransferSolInstructionDataEncoder } from '../../../lib/solana-program/system';
import { fetchJson } from '../../../util/fetch';
import { buildTokenSlug } from '../../common/tokens';
import { SOLANA_PROGRAM_IDS } from './constants';
import { parseTransactionForPreview } from './emulation';

jest.mock('../../../util/fetch', () => ({
  fetchJson: jest.fn(),
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

function transferToken(): Instruction {
  return {
    programAddress: SOLANA_PROGRAM_IDS.token[0] as Address,
    accounts: [
      { address: USER_TOKEN_ACCOUNT, role: AccountRole.WRITABLE },
      { address: ATTACKER_TOKEN_ACCOUNT, role: AccountRole.WRITABLE },
      { address: USER, role: AccountRole.READONLY_SIGNER },
    ],
    data: new Uint8Array([3, 100, 0, 0, 0, 0, 0, 0, 0]),
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

describe('parseTransactionForPreview', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('shows every SOL transfer of a transaction, not only the last one', async () => {
    const rawTx = buildRawTx([
      transferSol(ATTACKER, 10n * LAMPORTS_PER_SOL),
      transferSol(DECOY, 1n),
    ]);

    const { transfers, emulation } = await parseTransactionForPreview(rawTx, USER, 'mainnet');
    const activities = getTransactionActivities(emulation);

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
});
