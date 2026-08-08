// The API entrypoint loads this before anything under `chains/` runs; the test reaches `transfer`
// directly, so it has to bring the BigInt serializer itself or transfer logging throws.
import '../../../util/bigintPatch';

import { beginCell } from '@ton/core';

import type { ApiSubmitGaslessTransferOptions } from '../../types';

import { sendExternal } from './util/sendExternal';
import { getSigner } from './util/signer';
import { fetchStoredChainAccount } from '../../common/accounts';
import { buildTokenTransfer } from './tokens';
import { submitGaslessTransfer } from './transfer';
import { getTonWallet, getWalletInfo } from './wallet';

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('./tokens', () => ({
  buildTokenTransfer: jest.fn(),
  calculateTokenBalanceWithMintless: jest.fn(),
  getTokenBalanceWithMintless: jest.fn(),
}));

jest.mock('./util/sendExternal', () => ({ sendExternal: jest.fn() }));

// `getTonClient` reads the environment that `initApi` normally fills in.
jest.mock('../../environment', () => ({
  ...jest.requireActual('../../environment'),
  getEnvironment: () => ({ apiHeaders: {}, byNetwork: { mainnet: {}, testnet: {} } }),
}));

jest.mock('./util/signer', () => ({ getSigner: jest.fn() }));

jest.mock('./wallet', () => ({
  getContractInfo: jest.fn(),
  getTonWallet: jest.fn(),
  getWalletBalance: jest.fn(),
  getWalletInfo: jest.fn(),
  getWalletSeqno: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const FROM_ADDRESS = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAI7w';
const TO_ADDRESS = 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
const TOKEN_ADDRESS = 'EQCqC6EhRJ_tpWngKxL6dV0k6DSnRUrs9GSVkLbfdCqsj6TE';

function buildTransferOptions(): ApiSubmitGaslessTransferOptions {
  return {
    accountId: ACCOUNT_ID,
    enclaveToken: 'passcode:token',
    toAddress: TO_ADDRESS,
    amount: 1_000_000n,
    tokenAddress: TOKEN_ADDRESS,
    dieselAmount: 500_000n,
  } as ApiSubmitGaslessTransferOptions;
}

function createStubSigner() {
  return {
    isMock: false,
    signTransactions: jest.fn(() => [beginCell().endCell()]),
    signTonProof: jest.fn(),
    signMfaTransactions: jest.fn(),
    signInstallMfaRequest: jest.fn(),
    signRemoveMfaRequest: jest.fn(),
    signData: jest.fn(),
    encryptComment: jest.fn(),
    decryptComment: jest.fn(),
  } as unknown as Awaited<ReturnType<typeof getSigner>>;
}

describe('submitGaslessTransfer secret reads', () => {
  beforeEach(() => {
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({
      type: 'mnemonic',
      byChain: { ton: { address: FROM_ADDRESS, version: 'W5', publicKey: '00'.repeat(32) } },
    } as unknown as Awaited<ReturnType<typeof fetchStoredChainAccount>>);

    jest.mocked(buildTokenTransfer).mockImplementation(() => Promise.resolve({
      toAddress: TO_ADDRESS,
      amount: 50_000_000n,
    }) as ReturnType<typeof buildTokenTransfer>);

    jest.mocked(getTonWallet).mockReturnValue(
      { address: TO_ADDRESS } as unknown as ReturnType<typeof getTonWallet>,
    );
    jest.mocked(getWalletInfo).mockResolvedValue({
      seqno: 7,
      balance: 10_000_000_000n,
      isInitialized: true,
    } as Awaited<ReturnType<typeof getWalletInfo>>);

    jest.mocked(sendExternal).mockResolvedValue({
      boc: 'boc',
      msgHash: 'hash',
      msgHashNormalized: 'normalized-hash',
    } as Awaited<ReturnType<typeof sendExternal>>);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  // A signer reads the secret once, on its first signature, so one signer spends one Enclave session
  // usage. A gasless transfer is one operation and gets one usage, so it may build exactly one signer.
  it('constructs a single signer for one transfer', async () => {
    jest.mocked(getSigner).mockImplementation(() => createStubSigner());

    await submitGaslessTransfer(buildTransferOptions());

    expect(getSigner).toHaveBeenCalledTimes(1);
  });

  // The user-visible failure: the session dies with the first read, so a second read surfaces as
  // "wrong password" on a correct password.
  it('completes when the Enclave session grants a single secret read', async () => {
    let remainingReads = 1;
    jest.mocked(getSigner).mockImplementation(() => {
      if (remainingReads <= 0) {
        return {
          ...createStubSigner(),
          signTransactions: jest.fn(() => ({ error: 'Wrong password' })),
        } as unknown as ReturnType<typeof getSigner>;
      }

      remainingReads -= 1;
      return createStubSigner();
    });

    const result = await submitGaslessTransfer(buildTransferOptions());

    expect(result).not.toHaveProperty('error');
    expect(result).toHaveProperty('txId', 'normalized-hash');
  });
});
