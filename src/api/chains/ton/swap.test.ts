import { Address, beginCell, Cell } from '@ton/core';

import type { ApiAccountWithChain, ApiSwapBuildTransactionRequest } from '../../types';
import type { ApiBuildOnchainSwapTransferOptions, ApiSubmitOnchainSwapTransferOptions } from '../../types/swap';
import type { EmulationResponse } from './toncenter/emulation';

import { SWAP_FEE_ADDRESS } from '../../../config';
import { toDecimal } from '../../../util/decimals';
import honestTrace from './testData/uranusBuyV31EmulateTrace.json';
import poisonedTrace from './testData/uranusBuyV31Poison10EmulateTrace.json';
import { JettonOpCode, OpCode } from './constants';
import { buildOnchainSwapTransfer, submitOnchainSwapTransfer, validateDexSwapTransfers } from './swap';

const mockResolveTokenAddress = jest.fn();
const mockResolveTokenWalletAddress = jest.fn();
const mockGetTokenByAddress = jest.fn();
const mockGetContractInfo = jest.fn();
const mockValidateUranusBuyEmulation = jest.fn();

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/swap', () => ({ patchSwapItem: jest.fn() }));
jest.mock('../../common/tokens', () => ({
  ...jest.requireActual('../../common/tokens'),
  getTokenByAddress: (...args: unknown[]) => mockGetTokenByAddress(...args),
}));
jest.mock('../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
}));
jest.mock('./uranusBuyEmulation', () => ({
  ...jest.requireActual('./uranusBuyEmulation'),
  validateUranusBuyEmulation: (...args: unknown[]) => mockValidateUranusBuyEmulation(...args),
}));
jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  resolveTokenAddress: (...args: unknown[]) => mockResolveTokenAddress(...args),
  resolveTokenWalletAddress: (...args: unknown[]) => mockResolveTokenWalletAddress(...args),
}));
jest.mock('./wallet', () => ({
  getContractInfo: (...args: unknown[]) => mockGetContractInfo(...args),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredChainAccount, fetchStoredWallet } = require('../../common/accounts') as {
  fetchStoredChainAccount: jest.Mock;
  fetchStoredWallet: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { checkMultiTransactionDraft, submitMultiTransferWithMfa } = require('./transfer') as {
  checkMultiTransactionDraft: jest.Mock;
  submitMultiTransferWithMfa: jest.Mock;
};

const OWNER_ADDRESS = `0:${'1'.repeat(64)}`;
const TOKEN_ADDRESS = `0:${'2'.repeat(64)}`;
const TOKEN_WALLET_ADDRESS = `0:${'3'.repeat(64)}`;
const SWAP_ADDRESS = `0:${'4'.repeat(64)}`;

describe('buildOnchainSwapTransfer Uranus price verification', () => {
  const userAddress = 'EQDI24m89j6OUi_Qi0Es9DtdOEQgMgKvm6jhPb474bGk_F68';
  const masterAddress = 'EQAmoQqDz6woBJ1dvwFl14PHdD6CE3eVMd58INFRKp3n9Ycw';
  const buyPayload = beginCell().storeUint(0x94826557, 32).storeUint(0, 64)
    .storeCoins(1_000_000_000n).storeCoins(990_000_000n)
    .storeAddress(Address.parse(userAddress)).storeMaybeRef(undefined).storeMaybeRef(undefined).endCell();
  const feePayload = beginCell().storeUint(OpCode.OurFee, 32).endCell().toBoc().toString('base64');
  const options = {
    accountId: '0-mainnet', swapId: 'swap-id', authToken: 'auth-token', enclaveToken: 'enclave-token',
    request: {
      from: 'TON', to: masterAddress, fromAmount: '1.008827238', fromAddress: userAddress,
      toAmount: '1', toMinAmount: '0.99', slippage: 1, ourFee: '0.008827238', dieselFee: '0',
    },
    transfers: [
      { toAddress: masterAddress, amount: '1050000000', payload: buyPayload.toBoc().toString('base64') },
      { toAddress: SWAP_FEE_ADDRESS, amount: '8827238', payload: feePayload },
    ],
  } as ApiBuildOnchainSwapTransferOptions;

  beforeEach(() => {
    jest.clearAllMocks();
    mockValidateUranusBuyEmulation.mockReset();
    fetchStoredWallet.mockResolvedValue({ address: userAddress });
    fetchStoredChainAccount.mockResolvedValue({ byChain: { ton: { version: 'W5', address: userAddress } } });
    mockGetContractInfo.mockResolvedValue({
      isInitialized: true, isSwapAllowed: true,
      codeHash: 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
      contractInfo: {
        name: 'dedustUranusMemeV3_1', isSwapAllowed: true, nativeSwapPayload: 'dedustUranusMemepadBuy',
      },
    });
    mockResolveTokenWalletAddress.mockResolvedValue('0:aaaa');
  });

  function setupRealBuild(rawTrace: unknown, isPoisoned = false) {
    const trace = rawTrace as EmulationResponse;
    const masterTx = Object.values(trace.transactions).find((tx) => tx.in_msg.opcode === '0x94826557')!;
    const mint = masterTx.out_msgs.find((message) => message.opcode === '0x178d4519')!;
    const signerAddress = masterTx.in_msg.source!;
    const quoteOut = 659_198_488_073_850n / (isPoisoned ? 10n : 1n);
    const minOut = isPoisoned ? 65_260_650_319_311n : 652_606_503_193_111n;
    fetchStoredWallet.mockResolvedValue({ address: signerAddress });
    fetchStoredChainAccount.mockResolvedValue({
      byChain: { ton: { version: 'W5', address: signerAddress } },
    });
    mockResolveTokenWalletAddress.mockResolvedValue(mint.destination);
    mockValidateUranusBuyEmulation.mockImplementation((value) => {
      const actual = jest.requireActual<typeof import('./uranusBuyEmulation')>('./uranusBuyEmulation');
      return actual.validateUranusBuyEmulation(value);
    });
    checkMultiTransactionDraft.mockImplementation((_id, _messages, _gasless, onRawTrace) => {
      onRawTrace(trace);
      return Promise.resolve({ emulation: { isFallback: false, networkFee: 0n } });
    });
    return {
      ...options,
      request: {
        ...options.request,
        fromAddress: signerAddress,
        toAmount: toDecimal(quoteOut, 9),
        toMinAmount: toDecimal(minOut, 9),
      },
      transfers: [
        { toAddress: masterAddress, amount: '1050000000', payload: masterTx.in_msg.message_content.body },
        { toAddress: SWAP_FEE_ADDRESS, amount: '8827238', payload: feePayload },
      ],
    } as ApiBuildOnchainSwapTransferOptions;
  }

  it('accepts a real DeDust build only after validating its exact Toncenter trace', async () => {
    await expect(buildOnchainSwapTransfer(setupRealBuild(honestTrace)))
      .resolves.toEqual(expect.objectContaining({ chain: 'ton' }));
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(1);
  });

  it('still checks the exact Toncenter trace for a zero-fee Uranus buy', async () => {
    const zeroFeeBuild = setupRealBuild(honestTrace);
    zeroFeeBuild.request.fromAmount = '1';
    zeroFeeBuild.request.ourFee = '0';
    zeroFeeBuild.transfers = zeroFeeBuild.transfers!.slice(0, 1);

    await expect(buildOnchainSwapTransfer(zeroFeeBuild))
      .resolves.toEqual(expect.objectContaining({ chain: 'ton' }));
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(1);
    expect(mockValidateUranusBuyEmulation).toHaveBeenCalledTimes(1);
  });

  it('rejects a real build shape when the whole quote and signed minimum are poisoned ×0.1', async () => {
    await expect(buildOnchainSwapTransfer(setupRealBuild(poisonedTrace, true)))
      .resolves.toEqual({ error: 'uranus-price-drift' });
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(1);
  });

  it('rejects a poisoned zero-fee quote using the same independent trace bound', async () => {
    const zeroFeeBuild = setupRealBuild(poisonedTrace, true);
    zeroFeeBuild.request.fromAmount = '1';
    zeroFeeBuild.request.ourFee = '0';
    zeroFeeBuild.transfers = zeroFeeBuild.transfers!.slice(0, 1);

    await expect(buildOnchainSwapTransfer(zeroFeeBuild))
      .resolves.toEqual({ error: 'uranus-price-drift' });
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(1);
  });

  it('uses the same draft emulation once and passes its raw trace to the price verifier', async () => {
    const rawTrace = { trace: { tx_hash: 'raw-trace' } };
    checkMultiTransactionDraft.mockImplementation((_id, _messages, _gasless, onRawTrace) => {
      onRawTrace(rawTrace);
      return Promise.resolve({ emulation: { isFallback: false, networkFee: 0n } });
    });

    await expect(buildOnchainSwapTransfer(options)).resolves.toEqual(expect.objectContaining({ chain: 'ton' }));
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(1);
    expect(mockValidateUranusBuyEmulation).toHaveBeenCalledWith(expect.objectContaining({
      trace: rawTrace, masterAddress, signerAddress: userAddress,
      minimalAmountOut: 990_000_000n,
    }));
  });

  it('fails closed when draft emulation falls back or omits the raw trace', async () => {
    checkMultiTransactionDraft.mockResolvedValueOnce({ emulation: { isFallback: true, networkFee: 0n } });
    await expect(buildOnchainSwapTransfer(options)).rejects.toThrow('requires a complete on-chain emulation');
    expect(mockValidateUranusBuyEmulation).not.toHaveBeenCalled();

    checkMultiTransactionDraft.mockResolvedValueOnce({ emulation: { isFallback: false, networkFee: 0n } });
    await expect(buildOnchainSwapTransfer(options)).rejects.toThrow('requires a complete on-chain emulation');
    expect(checkMultiTransactionDraft).toHaveBeenCalledTimes(2);
  });
});

describe('submitOnchainSwapTransfer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchStoredWallet.mockResolvedValue({ address: 'EQ-wallet' });
    fetchStoredChainAccount.mockResolvedValue({ byChain: { ton: {} } });
    submitMultiTransferWithMfa.mockResolvedValue({
      msgHash: 'raw-boc-hash',
      msgHashNormalized: 'normalized-external-hash',
      messages: [{}],
      withW5Gasless: true,
    });
  });

  it('keeps local reconciliation metadata after a successful TON submit', async () => {
    const onUpdate = jest.fn();
    const localSwap = {
      id: 'swap-id::local',
      kind: 'swap',
      timestamp: 1,
      from: 'TON',
      fromAmount: '1',
      to: 'ton-token',
      toAmount: '2',
      networkFee: '0',
      swapFee: '0',
      ourFee: '0',
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    } as const;
    const options = {
      accountId: '0-mainnet',
      enclaveToken: 'enclave-token',
      transfers: [{
        amount: '1',
        payload: Cell.EMPTY.toBoc().toString('base64'),
        toAddress: 'EQ-destination',
      }],
      historyItem: { from: 'TON' },
      isGasless: false,
      authToken: 'auth-token',
      localSwap,
      swapId: 'swap-id',
    } as unknown as ApiSubmitOnchainSwapTransferOptions;

    const result = await submitOnchainSwapTransfer(options, onUpdate);

    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'newLocalActivities',
      activities: [expect.objectContaining({
        externalMsgHashNorm: 'normalized-external-hash',
        extra: expect.objectContaining({
          withW5Gasless: true,
          reconciliation: expect.objectContaining({
            operationId: 'swap:swap-id',
            reason: 'local-intent',
          }),
        }),
      })],
    }));
    expect(result).toEqual({
      activityId: 'swap-id::local',
      submittedHashes: ['raw-boc-hash', 'normalized-external-hash'],
    });
  });
});

describe('validateDexSwapTransfers', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockResolveTokenAddress.mockRejectedValue(new Error('Token wallet is not deployed'));
    mockResolveTokenWalletAddress.mockResolvedValue(TOKEN_WALLET_ADDRESS);
    mockGetTokenByAddress.mockReturnValue({
      decimals: 9,
      tokenAddress: TOKEN_ADDRESS,
    });
    mockGetContractInfo.mockResolvedValue({
      isSwapAllowed: true,
      codeHash: 'code-hash',
    });
  });

  it('accepts a valid transfer payload before a mintless token wallet is deployed', async () => {
    const payload = beginCell()
      .storeUint(JettonOpCode.Transfer, 32)
      .storeUint(1n, 64)
      .storeCoins(2n)
      .storeAddress(Address.parse(SWAP_ADDRESS))
      .storeAddress(Address.parse(OWNER_ADDRESS))
      .storeMaybeRef(undefined)
      .storeCoins(0n)
      .storeBit(0)
      .endCell();
    const request = {
      from: 'ton-token',
      fromAmount: '1',
    } as ApiSwapBuildTransactionRequest;
    const account = {
      type: 'mnemonic',
      byChain: { ton: { version: 'W5' } },
    } as unknown as ApiAccountWithChain<'ton'>;

    await expect(validateDexSwapTransfers('mainnet', OWNER_ADDRESS, request, [{
      toAddress: TOKEN_WALLET_ADDRESS,
      amount: 1n,
      payload,
    }], account)).resolves.toBeUndefined();

    expect(mockResolveTokenAddress).not.toHaveBeenCalled();
  });
});
