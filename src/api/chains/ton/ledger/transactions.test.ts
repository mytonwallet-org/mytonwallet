import { DeviceModelId } from '@ledgerhq/devices';
import { Address, beginCell, Cell, internal, SendMode } from '@ton/core';
import type { TonPayloadFormat } from '@ton-community/ton-ledger';
import nacl from 'tweetnacl';

import type { ApiTonWalletVersion, PreparedTransactionToSign, TokenTransferBodyParams } from '../types';

import { DEFAULT_WALLET_VERSION, TON_TSUSDE } from '../../../../config';
import { logDebug, logDebugError } from '../../../../util/logs';
import { randomBytes } from '../../../../util/random';
import { encryptMessageComment } from '../util/encryption';
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
} from '../util/tonCore';
import { DnsItem } from '../contracts/DnsItem';
import { TsUSDeWallet } from '../contracts/Ethena/TsUSDeWallet';
import { mockTonAddresses, mockTonBounceableAddresses } from '../../../../../tests/mocks';
import { expectAddress, expectCell } from '../../../../../tests/util/matchers';
import { NFT_TRANSFER_FORWARD_AMOUNT, TON_GAS } from '../constants';
import { buildNftTransferPayload } from '../nfts';
import {
  lacksBlindSigningError,
  type LedgerTransactionParams,
  tonPayloadToLedgerPayload,
  tonTransactionToLedgerTransaction,
  unsupportedError,
} from './transactions';

const sampleKnownJettons = [
  // Added in TON App 2.2
  {
    tokenAddress: 'EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT',
    knownJetton: { workchain: 0, jettonId: 1 },
    tokenWalletAddress: 'EQA6uJSiYt0aYIta0Wlm71w0va04kpre7XSTCKM3bKCwvkL2',
  },
  // Added in TON App 2.6.1
  {
    tokenAddress: 'EQD-cvR0Nz6XAyRBvbhz-abTrRC6sI5tvHvvpeQraV9UAAD7',
    knownJetton: { workchain: 0, jettonId: 7 },
    tokenWalletAddress: 'EQDU2CT5BziNK9oQGyYxRjkOMk4FBnbPO9XxVA5rIufr2ymz',
  },
];

jest.mock('../../../../util/logs');
jest.mock('../util/tonCore', () => ({
  ...jest.requireActual('../util/tonCore'),
  resolveTokenAddress: jest.fn().mockImplementation((network, jettonWallet) => {
    const sampleToken = sampleKnownJettons.find((jetton) => jetton.tokenWalletAddress === jettonWallet);
    if (network !== 'mainnet' || !sampleToken) {
      throw new Error(`${jettonWallet} is not a jetton wallet`);
    }
    return sampleToken.tokenAddress;
  }),
}));

afterEach(() => {
  (logDebug as jest.Mock).mockReset();
  (logDebugError as jest.Mock).mockReset();
  (resolveTokenAddress as jest.Mock).mockClear();
});

describe('tonTransactionToLedgerTransaction', () => {
  type TestCase = {
    // Input:
    walletVersion?: ApiTonWalletVersion;
    tonTransaction: PreparedTransactionToSign;
    ledgerModel?: DeviceModelId;
    ledgerTonVersion?: string;
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
      const token = sampleKnownJettons[0];
      return {
        tonTransaction: makeMockTonTransaction({
          hints: {
            tokenAddress: token.tokenAddress,
          },
        }, {
          body: makeMockTokenTransferPayload({
            tokenAmount,
            toAddress,
          }),
        }),
        ledgerTonVersion: '2.2.0',
        ledgerTransaction: expect.objectContaining({
          payload: expect.objectContaining({
            type: 'jetton-transfer',
            amount: tokenAmount,
            destination: expectAddress(Address.parse(toAddress)),
            knownJetton: token.knownJetton,
          }),
        }),
        expectResolvedTokenWallet: undefined,
      };
    },

    'token transfer with hint and without known jetton support (old TON App)': () => {
      const token = sampleKnownJettons[0];
      return makeSimpleTokenTransferCase({
        tokenWalletAddress: token.tokenWalletAddress,
        tokenAddressHint: token.tokenAddress,
        ledgerTonVersion: '2.1.0',
        expectedKnownJetton: undefined,
      });
    },

    'token transfer without hint': () => {
      const token = sampleKnownJettons[1];
      return makeSimpleTokenTransferCase({
        tokenWalletAddress: token.tokenWalletAddress,
        expectedKnownJetton: token.knownJetton,
        expectTokenAddressResolution: true,
      });
    },

    'token transfer without hint and without known jetton support (old TON App)': makeSimpleTokenTransferCase({
      tokenWalletAddress: sampleKnownJettons[0].tokenWalletAddress,
      ledgerTonVersion: '2.1.0',
      expectedKnownJetton: undefined,
    }),

    'token transfer without hint and without known jetton support (Ledger Nano S)': makeSimpleTokenTransferCase({
      tokenWalletAddress: sampleKnownJettons[1].tokenWalletAddress,
      ledgerModel: DeviceModelId.nanoS,
      expectedKnownJetton: undefined,
    }),

    'token transfer with unknown jetton': makeSimpleTokenTransferCase({
      tokenWalletAddress: mockTonBounceableAddresses[0],
      tokenAddressHint: mockTonBounceableAddresses[1],
      expectedKnownJetton: undefined,
    }),

    'token transfer with unsupported jetton id': () => {
      const freshToken = sampleKnownJettons[1];
      return makeSimpleTokenTransferCase({
        tokenWalletAddress: freshToken.tokenWalletAddress,
        tokenAddressHint: freshToken.tokenAddress,
        ledgerTonVersion: '2.2.0',
        expectedKnownJetton: undefined,
      });
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
      ledgerTonVersion: '2.0.0',
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
      ledgerTonVersion: '2.1.0',
      ledgerTransaction: lacksBlindSigningError,
    },

    'unsafe payload with blind signing enabled': () => {
      const tonPayload = makeMockTonPayload();
      return {
        tonTransaction: makeMockTonTransaction({}, {
          body: tonPayload,
        }),
        isBlindSigningEnabled: true,
        ledgerTonVersion: '2.1.0',
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
      ledgerModel = DeviceModelId.nanoX,
      ledgerTonVersion = '2.7.0',
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
      ledgerModel,
      ledgerTonVersion,
      isBlindSigningEnabled,
      subwalletId,
    ))[ledgerTransaction instanceof Error ? 'rejects' : 'resolves'].toEqual(ledgerTransaction);

    if (expectResolvedTokenWallet) {
      expect(resolveTokenAddress).toHaveBeenCalledTimes(1);
      expect(resolveTokenAddress).toHaveBeenCalledWith(network, expectResolvedTokenWallet);
    } else {
      expect(resolveTokenAddress).not.toHaveBeenCalled();
    }

    expect(logDebugError).not.toHaveBeenCalled();
  });

  function makeSimpleTokenTransferCase({
    tokenWalletAddress,
    tokenAddressHint,
    expectedKnownJetton,
    expectTokenAddressResolution,
    ...restOptions
  }: Partial<TestCase> & {
    tokenWalletAddress: string;
    tokenAddressHint?: string;
    expectedKnownJetton: { jettonId: number; workchain: number } | undefined;
    expectTokenAddressResolution?: boolean;
  }): TestCase {
    return {
      ...restOptions,
      tonTransaction: makeMockTonTransaction({
        hints: tokenAddressHint ? { tokenAddress: tokenAddressHint } : undefined,
      }, {
        to: tokenWalletAddress,
        body: makeMockTokenTransferPayload(),
      }),
      ledgerTransaction: expect.objectContaining({
        payload: expect.objectContaining({
          knownJetton: expectedKnownJetton ?? null, // eslint-disable-line no-null/no-null
        }),
      }),
      expectResolvedTokenWallet: expectTokenAddressResolution ? tokenWalletAddress : undefined,
    };
  }
});

/**
 * This test should contain all the payload types that the application generates (except for payloads from dapps)
 */
describe('tonPayloadToLedgerPayload', () => {
  type TestCase = {
    // Input:
    tonPayload: Cell | undefined;
    ledgerTonVersion?: string;

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
        tonPayload: buildNftTransferPayload({ fromAddress, toAddress, isLedger: true }),
        ledgerPayload: {
          type: 'nft-transfer',
          queryId: null, // eslint-disable-line no-null/no-null
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
        tonPayload: buildNftTransferPayload({
          fromAddress: mockTonAddresses[0],
          toAddress: mockTonAddresses[1],
          payload,
          forwardAmount,
          isLedger: true,
        }),
        ledgerPayload: expect.objectContaining({
          customPayload: null, // eslint-disable-line no-null/no-null
          forwardAmount,
          forwardPayload: expectCell(payload),
        }),
      };
    },

    'token transfer': () => {
      const fromAddress = mockTonAddresses[0];
      const toAddress = mockTonAddresses[1];
      const amount = 42_000_000n;
      const forwardAmount = 3n;
      const queryId = 0n;

      return {
        tonPayload: buildTokenTransferBody({
          tokenAmount: amount,
          toAddress,
          forwardAmount,
          responseAddress: fromAddress,
          queryId,
        }),
        ledgerPayload: {
          type: 'jetton-transfer',
          queryId: null, // eslint-disable-line no-null/no-null
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
      ledgerTonVersion: '2.0.0',
      ledgerPayload: 'unsupported',
    },
  };

  test.each(Object.entries(testCases))('%s', async (_, testCase) => {
    const resolvedTestCase = typeof testCase === 'function' ? await testCase() : testCase;
    const { tonPayload, ledgerTonVersion = '2.8.1', ledgerPayload } = resolvedTestCase;
    const runFunction = tonPayloadToLedgerPayload.bind(undefined, tonPayload, ledgerTonVersion);

    if (ledgerPayload === 'unsupported') {
      expect(runFunction).toThrow(unsupportedError);
      expect(logDebug).toHaveBeenCalledWith(
        expect.stringContaining(`payload type is not supported by Ledger TON v${ledgerTonVersion}`),
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

    expect(logDebugError).not.toHaveBeenCalled();
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
    queryId: 0n,
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
