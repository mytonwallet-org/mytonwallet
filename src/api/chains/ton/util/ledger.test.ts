import { Address, beginCell, Cell, internal, SendMode } from '@ton/core';
import type { TonPayloadFormat } from '@ton-community/ton-ledger';
import nacl from 'tweetnacl';

import type { ApiTonWalletVersion, PreparedTransactionToSign, TokenTransferBodyParams } from '../types';
import type { LedgerTransactionParams } from './ledger';

import { DEFAULT_WALLET_VERSION, TON_TSUSDE } from '../../../../config';
import { logDebug } from '../../../../util/logs';
import { randomBytes } from '../../../../util/random';
import { DnsItem } from '../contracts/DnsItem';
import { TsUSDeWallet } from '../contracts/Ethena/TsUSDeWallet';
import { mockTonAddresses, mockTonBounceableAddresses } from '../../../../../tests/mocks';
import { expectAddress, expectCell } from '../../../../../tests/util/matchers';
import { NFT_TRANSFER_FORWARD_AMOUNT, TON_GAS, WORKCHAIN } from '../constants';
import { buildNftTransferPayload } from '../nfts';
import { encryptMessageComment } from './encryption';
import { lacksBlindSigningError } from './ledger';
import { tonPayloadToLedgerPayload, tonTransactionToLedgerTransaction, unsupportedError } from './ledger';
import {
  buildJettonClaimPayload,
  buildJettonUnstakePayload,
  buildLiquidStakingDepositBody,
  buildLiquidStakingWithdrawBody,
  buildLiquidStakingWithdrawCustomPayload,
  buildTokenTransferBody,
  commentToBytes,
  packBytesAsSnakeCell,
  packBytesAsSnakeForEncryptedData,
  resolveTokenAddress,
} from './tonCore';

const sampleTokenAddress = 'EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT';
const sampleTokenKnownJetton = { workchain: WORKCHAIN, jettonId: 1 };

jest.mock('../../../../util/logs');
jest.mock('./tonCore', () => ({
  ...jest.requireActual('./tonCore'),
  resolveTokenAddress: jest.fn().mockResolvedValue(sampleTokenAddress),
}));

afterEach(() => {
  (logDebug as jest.Mock).mockReset();
  (resolveTokenAddress as jest.Mock).mockClear();
});

describe('tonTransactionToLedgerTransaction', () => {
  type TestCase = {
    // Input:
    walletVersion?: ApiTonWalletVersion;
    tonTransaction: PreparedTransactionToSign;
    ledgerVersion?: string;
    isBlindSigningEnabled?: boolean;
    subwalletId?: number;

    // Expectation:
    ledgerTransaction: LedgerTransactionParams | Error;
    expectResolvedTokenWallet?: string;
  };

  const testCases: Record<string, TestCase | (() => MaybePromise<TestCase>)> = {
    'ton transfer': () => {
      const amount = 111_000n;
      const toAddress = mockTonAddresses[0];
      const toAddressBounce = Math.random() < 0.5;
      const stateInit = { code: Cell.EMPTY, data: Cell.EMPTY };
      const seqno = 234;
      const sendMode = SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS;
      const timeout = 1723394029;
      return {
        tonTransaction: {
          seqno,
          messages: [internal({
            value: amount,
            to: toAddress,
            bounce: toAddressBounce,
            init: stateInit,
          })],
          sendMode,
          timeout,
        },
        ledgerTransaction: {
          to: expectAddress(Address.parse(toAddress)),
          sendMode,
          seqno,
          timeout,
          bounce: toAddressBounce,
          amount,
          stateInit,
        },
      };
    },

    'token transfer with hint': () => {
      const tokenAmount = 200_000n;
      const toAddress = mockTonAddresses[0];
      return {
        tonTransaction: makeMockTonTransaction({
          hints: {
            tokenAddress: sampleTokenAddress,
          },
        }, {
          body: makeMockTokenTransferPayload({
            tokenAmount,
            toAddress,
          }),
        }),
        ledgerVersion: '2.2.0',
        ledgerTransaction: expect.objectContaining({
          payload: expect.objectContaining({
            type: 'jetton-transfer',
            amount: tokenAmount,
            destination: expectAddress(Address.parse(toAddress)),
            knownJetton: sampleTokenKnownJetton,
          }),
        }),
        expectResolvedTokenWallet: undefined,
      };
    },

    'token transfer with hint and without known jetton Ledger support': {
      tonTransaction: makeMockTonTransaction({
        hints: {
          tokenAddress: sampleTokenAddress,
        },
      }, {
        body: makeMockTokenTransferPayload(),
      }),
      ledgerVersion: '2.1.0',
      ledgerTransaction: expect.objectContaining({
        payload: expect.objectContaining({
          knownJetton: null, // eslint-disable-line no-null/no-null
        }),
      }),
      expectResolvedTokenWallet: undefined,
    },

    'token transfer without hint': () => {
      const tokenWalletAddress = mockTonBounceableAddresses[0];
      return {
        tonTransaction: makeMockTonTransaction({}, {
          to: tokenWalletAddress,
          body: makeMockTokenTransferPayload(),
        }),
        ledgerVersion: '2.2.0',
        ledgerTransaction: expect.objectContaining({
          payload: expect.objectContaining({
            knownJetton: sampleTokenKnownJetton,
          }),
        }),
        expectResolvedTokenWallet: tokenWalletAddress,
      };
    },

    'token transfer without hint and without known jetton Ledger support': {
      tonTransaction: makeMockTonTransaction({}, {
        body: makeMockTokenTransferPayload(),
      }),
      ledgerVersion: '2.1.0',
      ledgerTransaction: expect.objectContaining({
        payload: expect.objectContaining({
          knownJetton: null, // eslint-disable-line no-null/no-null
        }),
      }),
      expectResolvedTokenWallet: undefined,
    },

    'token transfer with unknown jetton': {
      tonTransaction: makeMockTonTransaction({
        hints: {
          tokenAddress: mockTonBounceableAddresses[1],
        },
      }, {
        body: makeMockTokenTransferPayload(),
      }),
      ledgerVersion: '2.2.0',
      ledgerTransaction: expect.objectContaining({
        payload: expect.objectContaining({
          knownJetton: null, // eslint-disable-line no-null/no-null
        }),
      }),
      expectResolvedTokenWallet: undefined,
    },

    'with subwallet id': () => {
      const subwalletId = 987654;
      return {
        tonTransaction: makeMockTonTransaction(),
        subwalletId,
        ledgerTransaction: expect.objectContaining({
          walletSpecifiers: {
            subwalletId,
            includeWalletOp: false,
          },
        }),
      };
    },

    'v3R2 wallet': {
      walletVersion: 'v3R2',
      tonTransaction: makeMockTonTransaction(),
      ledgerTransaction: expect.objectContaining({
        walletSpecifiers: {
          includeWalletOp: false,
        },
      }),
    },

    'payload not supported by the Ledger version': {
      tonTransaction: makeMockTonTransaction({}, {
        body: buildLiquidStakingDepositBody(),
      }),
      ledgerVersion: '2.0.0',
      ledgerTransaction: unsupportedError,
    },

    'internal transaction': () => {
      const authType = 'internal';
      return {
        tonTransaction: makeMockTonTransaction({ authType }),
        ledgerTransaction: new Error(`Unsupported transaction authType "${authType}"`),
      };
    },

    'unsafe payload with blind signing disabled': {
      tonTransaction: makeMockTonTransaction({}, {
        body: makeMockTonPayload(),
      }),
      ledgerVersion: '2.1.0',
      ledgerTransaction: lacksBlindSigningError,
    },

    'unsafe payload with blind signing enabled': () => {
      const tonPayload = makeMockTonPayload();
      return {
        tonTransaction: makeMockTonTransaction({}, {
          body: tonPayload,
        }),
        isBlindSigningEnabled: true,
        ledgerVersion: '2.1.0',
        ledgerTransaction: expect.objectContaining({
          payload: {
            type: 'unsafe',
            message: tonPayload,
          },
        }),
      };
    },
  };

  test.each(Object.entries(testCases))('%s', async (_, testCase) => {
    const resolvedTestCase = typeof testCase === 'function' ? await testCase() : testCase;
    const {
      walletVersion = DEFAULT_WALLET_VERSION,
      tonTransaction,
      ledgerVersion = '2.2.0',
      isBlindSigningEnabled = false,
      subwalletId,
      ledgerTransaction,
      expectResolvedTokenWallet,
    } = resolvedTestCase;
    const network = 'mainnet';

    await expect(tonTransactionToLedgerTransaction(
      network,
      walletVersion,
      tonTransaction,
      ledgerVersion,
      isBlindSigningEnabled,
      subwalletId,
    ))[ledgerTransaction instanceof Error ? 'rejects' : 'resolves'].toEqual(ledgerTransaction);

    if (expectResolvedTokenWallet) {
      expect(resolveTokenAddress).toHaveBeenCalledTimes(1);
      expect(resolveTokenAddress).toHaveBeenCalledWith(network, expectResolvedTokenWallet);
    } else {
      expect(resolveTokenAddress).not.toHaveBeenCalled();
    }
  });
});

/**
 * This test should contain all the payload types that the application generates (except for payloads from dapps)
 */
describe('tonPayloadToLedgerPayload', () => {
  type TestCase = {
    // Input:
    tonPayload: Cell | undefined;
    ledgerVersion?: string;

    // Expectation:
    ledgerPayload: TonPayloadFormat | 'unsafe' | 'unsupported' | undefined;
  };

  const testCases: Record<string, TestCase | (() => MaybePromise<TestCase>)> = {
    'no payload': {
      tonPayload: undefined,
      ledgerPayload: undefined,
    },

    comment: () => {
      const comment = 'Hello, world';
      return {
        tonPayload: packBytesAsSnakeCell(commentToBytes(comment)),
        ledgerPayload: {
          type: 'comment',
          text: comment,
        },
      };
    },

    'Ledger-invalid comment': {
      tonPayload: packBytesAsSnakeCell(commentToBytes('😎👍')),
      ledgerPayload: 'unsafe',
    },

    'encrypted comment': async () => {
      const myPrivateKey = randomBytes(32);
      const theirPrivateKey = randomBytes(32);
      return {
        tonPayload: packBytesAsSnakeForEncryptedData(await encryptMessageComment(
          'Top secret',
          nacl.sign.keyPair.fromSeed(myPrivateKey).publicKey,
          nacl.sign.keyPair.fromSeed(theirPrivateKey).publicKey,
          myPrivateKey,
          Address.parse(mockTonAddresses[0]),
        )),
        ledgerPayload: 'unsafe',
      };
    },

    NFT: () => {
      const fromAddress = mockTonAddresses[0];
      const toAddress = mockTonAddresses[1];
      return {
        tonPayload: buildNftTransferPayload(fromAddress, toAddress),
        ledgerPayload: {
          type: 'nft-transfer',
          queryId: expect.any(BigInt),
          newOwner: expectAddress(Address.parse(toAddress)),
          responseDestination: expectAddress(Address.parse(fromAddress)),
          customPayload: null, // eslint-disable-line no-null/no-null
          forwardAmount: NFT_TRANSFER_FORWARD_AMOUNT,
          forwardPayload: null, // eslint-disable-line no-null/no-null
        },
      };
    },

    'NFT with payload': () => {
      const payload = packBytesAsSnakeCell(commentToBytes('Hello, world'));
      const forwardAmount = 20n;
      return {
        tonPayload: buildNftTransferPayload(mockTonAddresses[0], mockTonAddresses[1], payload, forwardAmount),
        ledgerPayload: expect.objectContaining({
          customPayload: null, // eslint-disable-line no-null/no-null
          forwardAmount,
          forwardPayload: payload,
        }),
      };
    },

    'token transfer': () => {
      const fromAddress = mockTonAddresses[0];
      const toAddress = mockTonAddresses[1];
      const amount = 42_000_000n;
      const forwardAmount = 3n;
      return {
        tonPayload: buildTokenTransferBody({
          tokenAmount: amount,
          toAddress,
          forwardAmount,
          responseAddress: fromAddress,
        }),
        ledgerPayload: {
          type: 'jetton-transfer',
          queryId: expect.any(BigInt),
          amount,
          destination: expectAddress(Address.parse(toAddress)),
          responseDestination: expectAddress(Address.parse(fromAddress)),
          customPayload: null, // eslint-disable-line no-null/no-null
          forwardAmount,
          forwardPayload: null, // eslint-disable-line no-null/no-null
          knownJetton: null, // eslint-disable-line no-null/no-null
        },
      };
    },

    'liquid stake': {
      tonPayload: buildLiquidStakingDepositBody(),
      ledgerPayload: {
        type: 'tonstakers-deposit',
        queryId: null, // eslint-disable-line no-null/no-null
        appId: null, // eslint-disable-line no-null/no-null
      },
    },

    'liquid stake with query id': () => {
      const queryId = 278492;
      return {
        tonPayload: buildLiquidStakingDepositBody(queryId),
        ledgerPayload: {
          type: 'tonstakers-deposit',
          queryId: BigInt(queryId),
          appId: null, // eslint-disable-line no-null/no-null
        },
      };
    },

    'liquid unstake': () => {
      const amount = 37_000n;
      const fromAddress = mockTonAddresses[0];
      const fillOrKill = Math.random() < 0.5;
      const waitTillRoundEnd = Math.random() < 0.5;
      return {
        tonPayload: buildLiquidStakingWithdrawBody({
          amount,
          responseAddress: fromAddress,
          fillOrKill,
          waitTillRoundEnd,
        }),
        ledgerPayload: {
          type: 'jetton-burn',
          queryId: null, // eslint-disable-line no-null/no-null
          amount,
          responseDestination: expectAddress(Address.parse(fromAddress)),
          customPayload: expectCell(buildLiquidStakingWithdrawCustomPayload(waitTillRoundEnd, fillOrKill)),
        },
      };
    },

    'jetton unstake': {
      tonPayload: buildJettonUnstakePayload(123_000n, true),
      ledgerPayload: 'unsafe',
    },

    'jetton claim': {
      tonPayload: buildJettonClaimPayload(mockTonAddresses.slice(0, 2)),
      ledgerPayload: 'unsafe',
    },

    'Ethena staking unlock': {
      tonPayload: TsUSDeWallet.transferTimelockedMessage({
        jettonAmount: 123_000n,
        to: Address.parse(TON_TSUSDE.tokenAddress),
        responseAddress: Address.parse(mockTonAddresses[0]),
        forwardTonAmount: TON_GAS.unstakeEthenaLockedForward,
      }),
      ledgerPayload: 'unsafe',
    },

    'TON DNS fill-up': {
      tonPayload: DnsItem.buildFillUpMessage(),
      ledgerPayload: {
        type: 'change-dns-record',
        queryId: null, // eslint-disable-line no-null/no-null
        record: {
          type: 'unknown',
          value: null, // eslint-disable-line no-null/no-null
          key: Buffer.alloc(32),
        },
      },
    },

    'TON DNS change': () => {
      const linkedAddress = mockTonAddresses[0];
      return {
        tonPayload: DnsItem.buildChangeDnsWalletMessage(linkedAddress),
        ledgerPayload: {
          type: 'change-dns-record',
          queryId: null, // eslint-disable-line no-null/no-null
          record: {
            type: 'wallet',
            value: {
              address: expectAddress(Address.parse(linkedAddress)),
              capabilities: null, // eslint-disable-line no-null/no-null
            },
          },
        },
      };
    },

    'payload not supported by the Ledger version': {
      tonPayload: buildLiquidStakingDepositBody(),
      ledgerVersion: '2.0.0',
      ledgerPayload: 'unsupported',
    },
  };

  test.each(Object.entries(testCases))('%s', async (_, testCase) => {
    const resolvedTestCase = typeof testCase === 'function' ? await testCase() : testCase;
    const { tonPayload, ledgerVersion = '2.1.0', ledgerPayload } = resolvedTestCase;
    const runFunction = tonPayloadToLedgerPayload.bind(undefined, tonPayload, ledgerVersion);

    if (ledgerPayload === 'unsupported') {
      expect(runFunction).toThrow(unsupportedError);
      expect(logDebug).toHaveBeenCalledWith(
        expect.stringContaining(`payload type is not supported by Ledger TON v${ledgerVersion}`),
      );
      return;
    }

    const expectedLedgerPayload = ledgerPayload === 'unsafe'
      ? { type: 'unsafe', message: tonPayload }
      : ledgerPayload;

    expect(runFunction()).toEqual(expectedLedgerPayload);
    if (expectedLedgerPayload?.type === 'unsafe') {
      expect(logDebug).toHaveBeenCalledWith('Unsafe Ledger payload', expect.any(Error));
    } else {
      expect(logDebug).not.toHaveBeenCalled();
    }
  });
});

function makeMockTonTransaction(
  transaction: Partial<PreparedTransactionToSign> = {},
  message: Partial<Parameters<typeof internal>[0]> = {},
): PreparedTransactionToSign {
  return {
    seqno: 839493,
    messages: [internal({
      to: mockTonAddresses[9],
      value: 8940643490n,
      ...message,
    })],
    sendMode: 0,
    timeout: Math.floor(Date.now() / 1000),
    ...transaction,
  };
}

function makeMockTokenTransferPayload(params: Partial<TokenTransferBodyParams> = {}) {
  return buildTokenTransferBody({
    tokenAmount: 20384232n,
    toAddress: mockTonAddresses[8],
    forwardAmount: 1n,
    responseAddress: mockTonAddresses[7],
    ...params,
  });
}

/** Returns a made-up TON payload definitely not supported by Ledger */
function makeMockTonPayload() {
  return beginCell()
    .storeUint(0x5E26E1, 24)
    .storeUint(0x110577C0, 32)
    .endCell();
}
