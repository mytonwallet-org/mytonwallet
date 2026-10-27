import { Wallet } from 'ethers';

import { ApiTransactionError } from '../../types';

import { fetchEvmWallet } from './util/account';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import { callHook } from '../../hooks';
import { submitBatchUserOp, validateEvmSwapCalls } from './smartAccount/batch';
import { isAlchemy7702Delegated } from './smartAccount/delegation';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { UNISWAP_PERMIT2_ADDRESS } from './constants';
import { getPermit2SignatureStrategy } from './permit2';
import {
  buildEvmSwapBatchCalls,
  buildLifiPermit2TypedData,
  buildPermit2PermitCall,
  buildSignedLifiPermit2Transaction,
  buildUniswapBatchCalls,
  encodeLifiPermit2Call,
  getEvmSwapAllowedTargets,
  getUniswapAllowedTargets,
  hasUniswapPermitData,
  parseEvmSwapTransactionPayload,
  parseUniswapTransactionPayload,
  resolveSwapGasLimit,
  resolveSwapNeedsBatch,
  shouldBatchUniswapSwap,
  shouldIncludePermit2AllowanceCall,
  signUniswapPermit2,
  submitLifiPermit2Swap,
  submitOnchainSwapTransfer,
} from './swap';

jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('./util/account', () => ({ fetchEvmWallet: jest.fn() }));
jest.mock('./auth', () => ({ fetchPrivateKeyString: jest.fn(), getSignerFromPrivateKey: jest.fn() }));
jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));
jest.mock('../../common/swap', () => ({ patchSwapItem: jest.fn() }));
jest.mock('../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./permit2', () => ({
  ...jest.requireActual('./permit2'),
  getPermit2SignatureStrategy: jest.fn(),
}));
jest.mock('./smartAccount/batch', () => ({
  estimateBatchUserOpFee: jest.fn(),
  submitBatchUserOp: jest.fn(),
  validateEvmSwapCalls: jest.fn(),
}));
jest.mock('./smartAccount/delegation', () => ({ isAlchemy7702Delegated: jest.fn() }));

const SAMPLE_PAYLOAD = {
  routing: 'CLASSIC',
  requiresPermitSignature: false,
  approval: {
    to: '0xToken',
    from: '0xWallet',
    data: '0xapprove',
    value: '0',
    chainId: 11155111,
  },
  swap: {
    to: '0xRouter',
    from: '0xWallet',
    data: '0xswap',
    value: '0',
    chainId: 11155111,
  },
};

const PERMIT2_APPROVAL_PAYLOAD = {
  ...SAMPLE_PAYLOAD,
  approval: {
    ...SAMPLE_PAYLOAD.approval,
    to: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    // eslint-disable-next-line @stylistic/max-len
    data: '0x095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  },
  swap: {
    ...SAMPLE_PAYLOAD.swap,
    to: '0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85',
  },
};

const PERMIT_DATA = {
  domain: {
    name: 'Permit2',
    chainId: 1,
    verifyingContract: UNISWAP_PERMIT2_ADDRESS,
  },
  types: {
    PermitSingle: [
      { name: 'details', type: 'PermitDetails' },
      { name: 'spender', type: 'address' },
      { name: 'sigDeadline', type: 'uint256' },
    ],
    PermitDetails: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
      { name: 'nonce', type: 'uint48' },
    ],
  },
  values: {
    details: {
      token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      amount: '100000',
      expiration: '1790073185',
      nonce: '0',
    },
    spender: '0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85',
    sigDeadline: '1790073185',
  },
};

const PERMIT_WALLET = Wallet.createRandom();

const PERMIT2_PERMIT_PAYLOAD = {
  ...PERMIT2_APPROVAL_PAYLOAD,
  requiresPermitSignature: true,
  permitData: PERMIT_DATA,
  approval: {
    ...PERMIT2_APPROVAL_PAYLOAD.approval,
    from: PERMIT_WALLET.address,
  },
  swap: {
    ...PERMIT2_APPROVAL_PAYLOAD.swap,
    from: PERMIT_WALLET.address,
  },
};

const LIFI_APPROVAL_PAYLOAD = {
  provider: 'lifi' as const,
  approval: {
    to: '0xToken',
    from: '0xWallet',
    data: '0xapprove',
    value: '0',
    chainId: 1,
  },
  swap: {
    to: '0xLifiRouter',
    from: '0xWallet',
    data: '0xlifiSwap',
    value: '0',
    chainId: 1,
  },
};

const LIFI_PERMIT2_PAYLOAD = {
  provider: 'lifi' as const,
  approval: {
    to: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    from: '0xWallet',
    data: '0xapprove',
    value: '0',
    chainId: 1,
  },
  lifiPermit2: {
    token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    amount: '1000000',
    permit2: UNISWAP_PERMIT2_ADDRESS,
    permit2Proxy: '0x89c6340B1a1f4b25D36cd8B063D49045caF3f818',
    deadlineSeconds: 1800,
    transactionRequest: {
      to: '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE',
      from: '0x1111111111111111111111111111111111111111',
      data: '0xa6010a66',
      value: '0',
      chainId: 1,
    },
  },
};

const LIFI_WITNESS_PAYLOAD = {
  ...LIFI_PERMIT2_PAYLOAD,
  lifiPermit2: {
    ...LIFI_PERMIT2_PAYLOAD.lifiPermit2,
    witness: {
      diamondAddress: LIFI_PERMIT2_PAYLOAD.lifiPermit2.transactionRequest.to,
    },
    transactionRequest: {
      ...LIFI_PERMIT2_PAYLOAD.lifiPermit2.transactionRequest,
      value: '0xb938657b5715',
    },
  },
};

const LIFI_BASE_PERMIT2_PAYLOAD = {
  ...LIFI_PERMIT2_PAYLOAD,
  approval: {
    ...LIFI_PERMIT2_PAYLOAD.approval,
    to: '0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2',
    chainId: 8453,
  },
  lifiPermit2: {
    ...LIFI_PERMIT2_PAYLOAD.lifiPermit2,
    token: '0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2',
    transactionRequest: {
      ...LIFI_PERMIT2_PAYLOAD.lifiPermit2.transactionRequest,
      chainId: 8453,
    },
  },
};

const OWNER = LIFI_PERMIT2_PAYLOAD.lifiPermit2.transactionRequest.from;
const SIGNATURE = `0x${'11'.repeat(65)}`;
const NEXT_NONCE_RESULT = `0x${'0'.repeat(63)}7`;
const provider = {
  call: jest.fn(),
  estimateGas: jest.fn(),
};
const signer = {
  signTypedData: jest.fn(),
  connect: jest.fn(),
};
const connectedSigner = {
  sendTransaction: jest.fn(),
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getEvmProvider).mockReturnValue(provider as never);
  jest.mocked(fetchEvmWallet).mockResolvedValue({ address: OWNER } as never);
  jest.mocked(fetchStoredWallet).mockResolvedValue({ address: 'ton-history-address' } as never);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ type: 'mnemonic' } as never);
  jest.mocked(fetchPrivateKeyString).mockResolvedValue(PERMIT_WALLET.privateKey);
  jest.mocked(patchSwapItem).mockResolvedValue(undefined as never);
  jest.mocked(callHook).mockReturnValue(undefined as never);
  jest.mocked(getSignerFromPrivateKey).mockReturnValue(signer as never);
  jest.mocked(getPermit2SignatureStrategy).mockResolvedValue('raw');
  jest.mocked(validateEvmSwapCalls).mockReturnValue(undefined);
  jest.mocked(submitBatchUserOp).mockResolvedValue({ txHash: '0xbatch', userOpHash: '0xuserop', success: true });
  provider.call.mockResolvedValue(NEXT_NONCE_RESULT);
  provider.estimateGas.mockResolvedValue(21_000n);
  signer.signTypedData.mockResolvedValue(SIGNATURE);
  signer.connect.mockReturnValue(connectedSigner);
  connectedSigner.sendTransaction.mockResolvedValue({ hash: '0xdirect' });
});

describe('buildUniswapBatchCalls', () => {
  it('builds approve + swap calls from backend payload', () => {
    expect(buildUniswapBatchCalls(SAMPLE_PAYLOAD)).toEqual([
      { to: '0xToken', value: 0n, data: '0xapprove' },
      { to: '0xRouter', value: 0n, data: '0xswap' },
    ]);
  });

  it('inserts Permit2.approve fallback when permitData is absent', () => {
    const calls = buildUniswapBatchCalls(PERMIT2_APPROVAL_PAYLOAD);

    expect(calls).toHaveLength(3);
    expect(calls[1].to).toBe(UNISWAP_PERMIT2_ADDRESS);
    expect(calls[1].data).toMatch(/^0x87517c45/);
  });

  it('uses a signed Permit2.permit call for backend permitData batches', async () => {
    const permitSignature = await signUniswapPermit2('mainnet', PERMIT_WALLET.privateKey, PERMIT_DATA);
    const calls = buildUniswapBatchCalls(PERMIT2_PERMIT_PAYLOAD, permitSignature);

    expect(calls).toHaveLength(3);
    expect(calls[1]).toEqual(buildPermit2PermitCall(
      PERMIT2_PERMIT_PAYLOAD.swap.from,
      PERMIT_DATA,
      permitSignature,
    ));
    expect(calls[1].data).toMatch(/^0x2b67b570/);
    expect(calls[2].to).toBe(PERMIT2_PERMIT_PAYLOAD.swap.to);
  });

  it('builds swap-only batch when approval is absent', () => {
    const payload = { ...SAMPLE_PAYLOAD, approval: undefined };

    expect(buildUniswapBatchCalls(payload)).toEqual([
      { to: '0xRouter', value: 0n, data: '0xswap' },
    ]);
  });
});

describe('buildEvmSwapBatchCalls', () => {
  it('builds provider-neutral LI.FI approve + swap calls without Uniswap Permit2 extras', () => {
    expect(buildEvmSwapBatchCalls(LIFI_APPROVAL_PAYLOAD)).toEqual([
      { to: '0xToken', value: 0n, data: '0xapprove' },
      { to: '0xLifiRouter', value: 0n, data: '0xlifiSwap' },
    ]);
  });

  it('allows only LI.FI approval and swap targets for provider-neutral payloads', () => {
    expect([...getEvmSwapAllowedTargets(LIFI_APPROVAL_PAYLOAD)].sort()).toEqual([
      '0xlifirouter',
      '0xtoken',
    ]);
  });

  it('allows LI.FI Permit2 approval and proxy targets', () => {
    expect([...getEvmSwapAllowedTargets(LIFI_PERMIT2_PAYLOAD)].sort()).toEqual([
      '0x89c6340b1a1f4b25d36cd8b063d49045caf3f818',
      '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    ]);
  });
});

describe('LI.FI Permit2 wrapping', () => {
  it('builds SDK-compatible PermitTransferFrom typed data', () => {
    const typedData = buildLifiPermit2TypedData(LIFI_PERMIT2_PAYLOAD, 7n, 12345n);

    expect(typedData.domain).toEqual({
      name: 'Permit2',
      chainId: 1,
      verifyingContract: UNISWAP_PERMIT2_ADDRESS,
    });
    expect(typedData.message).toEqual({
      permitted: {
        token: LIFI_PERMIT2_PAYLOAD.lifiPermit2.token,
        amount: LIFI_PERMIT2_PAYLOAD.lifiPermit2.amount,
      },
      spender: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
      nonce: 7n,
      deadline: 12345n,
    });
  });

  it('encodes callDiamondWithPermit2 with the same nonce and deadline as the signed payload', () => {
    const data = encodeLifiPermit2Call(LIFI_PERMIT2_PAYLOAD, 7n, 12345n, `0x${'11'.repeat(65)}`);

    expect(data).toMatch(/^0x/);
    expect(data.toLowerCase()).toContain('a6010a66');
    expect(data.toLowerCase()).toContain('0000000000000000000000000000000000000000000000000000000000000007');
    expect(data.toLowerCase()).toContain('0000000000000000000000000000000000000000000000000000000000003039');
  });

  it('builds SDK-compatible PermitWitnessTransferFrom typed data for payable LI.FI calls', () => {
    const typedData = buildLifiPermit2TypedData(LIFI_WITNESS_PAYLOAD, 7n, 12345n);

    expect(typedData.types).toEqual(expect.objectContaining({
      LiFiCall: [
        { name: 'diamondAddress', type: 'address' },
        { name: 'diamondCalldataHash', type: 'bytes32' },
      ],
      PermitWitnessTransferFrom: expect.arrayContaining([
        { name: 'witness', type: 'LiFiCall' },
      ]),
    }));
    expect(typedData.message).toEqual(expect.objectContaining({
      spender: LIFI_WITNESS_PAYLOAD.lifiPermit2.permit2Proxy,
      witness: {
        diamondAddress: LIFI_WITNESS_PAYLOAD.lifiPermit2.transactionRequest.to,
        diamondCalldataHash: expect.stringMatching(/^0x[0-9a-f]{64}$/u),
      },
    }));
  });

  it('encodes payable callDiamondWithPermit2Witness for native-value LI.FI routes', () => {
    const data = encodeLifiPermit2Call(LIFI_WITNESS_PAYLOAD, 7n, 12345n, `0x${'11'.repeat(65)}`, OWNER);

    expect(data).toMatch(/^0x/);
    expect(data).not.toEqual(encodeLifiPermit2Call(LIFI_PERMIT2_PAYLOAD, 7n, 12345n, `0x${'11'.repeat(65)}`));
    expect(data.toLowerCase()).toContain('a6010a66');
    expect(data.toLowerCase()).toContain(OWNER.slice(2).toLowerCase());
  });

  it('builds a signed wrapped transaction from live nonce and client deadline', async () => {
    const dateNow = jest.spyOn(Date, 'now').mockReturnValue(1_700_000_000_000);

    try {
      const transaction = await buildSignedLifiPermit2Transaction(
        'ethereum',
        'mainnet',
        OWNER,
        '0xprivate',
        LIFI_PERMIT2_PAYLOAD,
      );

      expect(getPermit2SignatureStrategy).toHaveBeenCalledWith('ethereum', 'mainnet', OWNER);
      expect(provider.call).toHaveBeenCalledWith({
        to: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
        data: expect.stringMatching(/^0x/),
      });
      expect(signer.signTypedData).toHaveBeenCalledWith(
        {
          name: 'Permit2',
          chainId: 1,
          verifyingContract: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2,
        },
        expect.objectContaining({ PermitTransferFrom: expect.any(Array) }),
        expect.objectContaining({
          permitted: {
            token: LIFI_PERMIT2_PAYLOAD.lifiPermit2.token,
            amount: LIFI_PERMIT2_PAYLOAD.lifiPermit2.amount,
          },
          spender: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
          nonce: 7n,
          deadline: 1_700_001_800n,
        }),
      );
      expect(transaction).toMatchObject({
        from: OWNER,
        to: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
        chainId: 1,
        value: '0',
      });
      expect('data' in transaction && transaction.data).toMatch(/^0x/);
    } finally {
      dateNow.mockRestore();
    }
  });

  it('builds LI.FI Permit2 transactions for non-Ethereum EVM chains from backend payload', async () => {
    const transaction = await buildSignedLifiPermit2Transaction(
      'base',
      'mainnet',
      OWNER,
      '0xprivate',
      LIFI_BASE_PERMIT2_PAYLOAD,
    );

    expect(getPermit2SignatureStrategy).toHaveBeenCalledWith('base', 'mainnet', OWNER);
    expect(signer.signTypedData).toHaveBeenCalledWith(
      {
        name: 'Permit2',
        chainId: 8453,
        verifyingContract: LIFI_BASE_PERMIT2_PAYLOAD.lifiPermit2.permit2,
      },
      expect.objectContaining({ PermitTransferFrom: expect.any(Array) }),
      expect.objectContaining({
        permitted: {
          token: LIFI_BASE_PERMIT2_PAYLOAD.lifiPermit2.token,
          amount: LIFI_BASE_PERMIT2_PAYLOAD.lifiPermit2.amount,
        },
        spender: LIFI_BASE_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
      }),
    );
    expect(transaction).toMatchObject({
      from: OWNER,
      to: LIFI_BASE_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
      chainId: 8453,
      value: '0',
    });
  });

  it('builds a signed payable witness transaction from live nonce and client deadline', async () => {
    const dateNow = jest.spyOn(Date, 'now').mockReturnValue(1_700_000_000_000);

    try {
      const transaction = await buildSignedLifiPermit2Transaction(
        'ethereum',
        'mainnet',
        OWNER,
        '0xprivate',
        LIFI_WITNESS_PAYLOAD,
      );

      expect(signer.signTypedData).toHaveBeenCalledWith(
        {
          name: 'Permit2',
          chainId: 1,
          verifyingContract: LIFI_WITNESS_PAYLOAD.lifiPermit2.permit2,
        },
        expect.objectContaining({
          LiFiCall: expect.any(Array),
          PermitWitnessTransferFrom: expect.any(Array),
        }),
        expect.objectContaining({
          witness: {
            diamondAddress: LIFI_WITNESS_PAYLOAD.lifiPermit2.transactionRequest.to,
            diamondCalldataHash: expect.stringMatching(/^0x[0-9a-f]{64}$/u),
          },
        }),
      );
      expect(transaction).toMatchObject({
        from: OWNER,
        to: LIFI_WITNESS_PAYLOAD.lifiPermit2.permit2Proxy,
        chainId: 1,
        value: '0xb938657b5715',
      });
      expect('data' in transaction && transaction.data).toMatch(/^0x/);
    } finally {
      dateNow.mockRestore();
    }
  });

  it('rejects accounts that cannot use Permit2 without falling back to approval flow', async () => {
    jest.mocked(getPermit2SignatureStrategy).mockResolvedValue(false);

    const result = await buildSignedLifiPermit2Transaction(
      'ethereum',
      'mainnet',
      OWNER,
      '0xprivate',
      LIFI_PERMIT2_PAYLOAD,
    );

    expect(result).toEqual({ error: ApiTransactionError.UnsuccesfulTransfer });
    expect(signer.signTypedData).not.toHaveBeenCalled();
    expect(provider.call).not.toHaveBeenCalled();
  });

  it('submits direct LI.FI Permit2 wrapped transactions', async () => {
    const result = await submitLifiPermit2Swap(
      'ethereum',
      'mainnet',
      OWNER,
      '0xprivate',
      { ...LIFI_PERMIT2_PAYLOAD, approval: undefined },
      false,
    );

    expect(result).toEqual({ txHash: '0xdirect' });
    expect(provider.estimateGas).toHaveBeenCalledWith(expect.objectContaining({
      from: OWNER,
      to: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
    }));
    expect(connectedSigner.sendTransaction).toHaveBeenCalledWith(expect.objectContaining({
      from: OWNER,
      to: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy,
      gasLimit: 31_500n,
    }));
    expect(submitBatchUserOp).not.toHaveBeenCalled();
  });

  it('submits batched approve-to-Permit2 plus LI.FI Permit2 wrapped transaction', async () => {
    const result = await submitLifiPermit2Swap(
      'ethereum',
      'mainnet',
      OWNER,
      '0xprivate',
      LIFI_PERMIT2_PAYLOAD,
      true,
    );

    expect(result).toEqual({ txHash: '0xbatch' });
    expect(validateEvmSwapCalls).toHaveBeenCalled();
    expect(submitBatchUserOp).toHaveBeenCalledWith(
      'ethereum',
      'mainnet',
      OWNER,
      '0xprivate',
      [
        expect.objectContaining({ to: LIFI_PERMIT2_PAYLOAD.approval.to }),
        expect.objectContaining({ to: LIFI_PERMIT2_PAYLOAD.lifiPermit2.permit2Proxy }),
      ],
    );
    expect(connectedSigner.sendTransaction).not.toHaveBeenCalled();
  });
});

describe('submitOnchainSwapTransfer', () => {
  it('sends a native-source LI.FI transaction request without Uniswap batching', async () => {
    const localSwap = {
      id: 'native-local',
      kind: 'swap',
      timestamp: 1_700_000_000,
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
    };
    const transactionRequest = {
      from: OWNER,
      to: '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE',
      data: '0xa6010a66',
      value: '30000000000000',
      chainId: 8453,
    };

    const result = await submitOnchainSwapTransfer('base', {
      accountId: '0-mainnet',
      enclaveToken: 'enclave',
      authToken: 'auth',
      localSwap,
      historyItem: localSwap,
      swapId: 'native-backend',
      transactionRequest,
      needsBatch: true,
    } as never, jest.fn());

    expect(result).toEqual({ activityId: 'native-local', submittedHashes: ['0xdirect'] });
    expect(connectedSigner.sendTransaction).toHaveBeenCalledWith(expect.objectContaining({
      to: transactionRequest.to,
      chainId: 8453,
      value: 30_000_000_000_000n,
    }));
    expect(signer.signTypedData).not.toHaveBeenCalled();
    expect(submitBatchUserOp).not.toHaveBeenCalled();
    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      swapId: 'native-backend', msgHash: '0xdirect',
    }));
  });

  it('signs and reports a LI.FI Permit2 swap through the real submit path', async () => {
    const onUpdate = jest.fn();
    const localSwap = {
      id: 'lifi-local',
      kind: 'swap',
      timestamp: 1_700_000_000,
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
    };
    const payload = { ...LIFI_PERMIT2_PAYLOAD, approval: undefined };

    const result = await submitOnchainSwapTransfer('ethereum', {
      accountId: '0-mainnet',
      enclaveToken: 'enclave',
      authToken: 'auth',
      localSwap,
      historyItem: localSwap,
      swapId: 'lifi-backend',
      transaction: JSON.stringify(payload),
      needsBatch: false,
    } as never, onUpdate);

    expect(result).toEqual({ activityId: 'lifi-local', submittedHashes: ['0xdirect'] });
    expect(signer.signTypedData).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Permit2' }),
      expect.objectContaining({ PermitTransferFrom: expect.any(Array) }),
      expect.objectContaining({ spender: payload.lifiPermit2.permit2Proxy }),
    );
    expect(connectedSigner.sendTransaction).toHaveBeenCalledWith(expect.objectContaining({
      to: payload.lifiPermit2.permit2Proxy,
    }));
    expect(submitBatchUserOp).not.toHaveBeenCalled();
    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      swapId: 'lifi-backend',
      msgHash: '0xdirect',
    }));
  });

  it('signs a payable LI.FI Stargate witness and reports the source hash', async () => {
    const localSwap = {
      id: 'bridge-local', kind: 'swap', timestamp: 1_700_000_000,
      status: 'pendingTrusted', hashes: [], transactionIds: {},
    };
    const result = await submitOnchainSwapTransfer('ethereum', {
      accountId: '0-mainnet', enclaveToken: 'enclave', authToken: 'auth',
      localSwap, historyItem: localSwap, swapId: 'bridge-backend',
      transaction: JSON.stringify({ ...LIFI_WITNESS_PAYLOAD, approval: undefined }),
      needsBatch: false,
    } as never, jest.fn());

    expect(result).toEqual({ activityId: 'bridge-local', submittedHashes: ['0xdirect'] });
    expect(signer.signTypedData).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Permit2' }),
      expect.objectContaining({ PermitWitnessTransferFrom: expect.any(Array) }),
      expect.objectContaining({ witness: expect.any(Object) }),
    );
    expect(connectedSigner.sendTransaction).toHaveBeenCalledWith(expect.objectContaining({
      to: LIFI_WITNESS_PAYLOAD.lifiPermit2.permit2Proxy,
      value: BigInt(LIFI_WITNESS_PAYLOAD.lifiPermit2.transactionRequest.value),
    }));
    expect(submitBatchUserOp).not.toHaveBeenCalled();
    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      swapId: 'bridge-backend', msgHash: '0xdirect',
    }));
  });

  it('signs Permit2 data before submitting a Uniswap approval batch', async () => {
    const onUpdate = jest.fn();
    const localSwap = {
      id: 'swap-local',
      kind: 'swap',
      timestamp: 1_700_000_000,
      status: 'pendingTrusted',
      hashes: [],
      transactionIds: {},
    };

    const result = await submitOnchainSwapTransfer('ethereum', {
      accountId: '0-mainnet',
      enclaveToken: 'enclave',
      authToken: 'auth',
      localSwap,
      historyItem: localSwap,
      swapId: 'swap-backend',
      transaction: JSON.stringify(PERMIT2_PERMIT_PAYLOAD),
      needsBatch: true,
    } as never, onUpdate);

    expect(result).toEqual({ activityId: 'swap-local', submittedHashes: ['0xbatch'] });
    expect(submitBatchUserOp).toHaveBeenCalledWith(
      'ethereum',
      'mainnet',
      OWNER,
      PERMIT_WALLET.privateKey,
      [
        expect.objectContaining({ to: PERMIT2_PERMIT_PAYLOAD.approval.to }),
        expect.objectContaining({
          to: UNISWAP_PERMIT2_ADDRESS,
          data: expect.stringMatching(/^0x2b67b570/),
        }),
        expect.objectContaining({ to: PERMIT2_PERMIT_PAYLOAD.swap.to }),
      ],
    );
    expect(validateEvmSwapCalls).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({
          to: UNISWAP_PERMIT2_ADDRESS,
          data: expect.stringMatching(/^0x2b67b570/),
        }),
      ]),
      expect.any(Set),
    );
    expect(patchSwapItem).toHaveBeenCalledWith(expect.objectContaining({
      address: 'ton-history-address',
      swapId: 'swap-backend',
      authToken: 'auth',
      msgHash: '0xbatch',
      msgHashNormalized: '0xbatch',
    }));
  });
});

describe('hasUniswapPermitData', () => {
  it('detects backend permitData payloads', () => {
    expect(hasUniswapPermitData(PERMIT2_PERMIT_PAYLOAD)).toBe(true);
    expect(hasUniswapPermitData(PERMIT2_APPROVAL_PAYLOAD)).toBe(false);
  });
});

describe('shouldBatchUniswapSwap', () => {
  it('batches when a Permit2 approve or a missing delegate is already known', () => {
    expect(shouldBatchUniswapSwap(SAMPLE_PAYLOAD, { needsBatch: true })).toBe(true);
    expect(shouldBatchUniswapSwap(SAMPLE_PAYLOAD, { needsDelegate: true })).toBe(true);
  });

  it('batches when Permit2 EIP-712 data is present and approve is not required', () => {
    const payload = { ...PERMIT2_PERMIT_PAYLOAD, approval: undefined };

    expect(shouldBatchUniswapSwap(payload)).toBe(true);
  });

  it('sends the router transaction directly when approve, permitData, and delegation are settled', () => {
    const payload = { ...SAMPLE_PAYLOAD, approval: undefined };

    expect(shouldBatchUniswapSwap(payload)).toBe(false);
  });
});

describe('shouldIncludePermit2AllowanceCall', () => {
  it('returns false when permitData is provided', () => {
    expect(shouldIncludePermit2AllowanceCall(PERMIT2_PERMIT_PAYLOAD)).toBe(false);
  });

  it('returns true when ERC20 approve targets Permit2 without permitData', () => {
    expect(shouldIncludePermit2AllowanceCall(PERMIT2_APPROVAL_PAYLOAD)).toBe(true);
  });
});

describe('parseUniswapTransactionPayload', () => {
  it('round-trips backend JSON payload', () => {
    const parsed = parseUniswapTransactionPayload(JSON.stringify(PERMIT2_PERMIT_PAYLOAD));

    expect(parsed.routing).toBe('CLASSIC');
    expect(parsed.permitData?.values.spender).toBe(PERMIT2_PERMIT_PAYLOAD.swap.to);
  });
});

describe('parseEvmSwapTransactionPayload', () => {
  it('accepts provider-neutral payloads without Uniswap permit fields', () => {
    const parsed = parseEvmSwapTransactionPayload(JSON.stringify(LIFI_APPROVAL_PAYLOAD));

    expect(parsed.provider).toBe('lifi');
    expect(parsed.approval?.to).toBe('0xToken');
    expect(parsed.swap?.to).toBe('0xLifiRouter');
  });
});

describe('getUniswapAllowedTargets', () => {
  it('includes approval and swap targets', () => {
    expect(getUniswapAllowedTargets(SAMPLE_PAYLOAD)).toEqual(new Set([
      '0xtoken',
      '0xrouter',
    ]));
  });

  it('includes Permit2 for permitData batches', () => {
    expect(getUniswapAllowedTargets(PERMIT2_PERMIT_PAYLOAD)).toEqual(new Set([
      '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      '0x23617e59a5925b2a4bf75d73ff6711cd0b29de85',
      UNISWAP_PERMIT2_ADDRESS.toLowerCase(),
    ]));
  });
});

describe('resolveSwapGasLimit', () => {
  it('applies swap gas headroom to eth_estimateGas result', () => {
    expect(resolveSwapGasLimit(182_181n)).toBe(273_271n);
  });

  it('prefers backend gasLimit when it is higher than buffered estimate', () => {
    expect(resolveSwapGasLimit(182_181n, '300000')).toBe(300_000n);
  });
});

describe('resolveSwapNeedsBatch', () => {
  const fetchWallet = fetchEvmWallet as jest.Mock;
  const isDelegated = isAlchemy7702Delegated as jest.Mock;

  beforeEach(() => {
    fetchWallet.mockReset();
    isDelegated.mockReset();
  });

  it('is true when the backend already requires a Permit2 approval', async () => {
    await expect(resolveSwapNeedsBatch('robinhood', '0-mainnet', true)).resolves.toBe(true);
    expect(fetchWallet).not.toHaveBeenCalled();
  });

  it('is true when the account has no Alchemy delegate', async () => {
    fetchWallet.mockResolvedValue({ address: '0xwallet' });
    isDelegated.mockResolvedValue(false);

    await expect(resolveSwapNeedsBatch('robinhood', '0-mainnet', false)).resolves.toBe(true);
    expect(isDelegated).toHaveBeenCalledWith('robinhood', 'mainnet', '0xwallet');
  });

  it('is false when the account is already delegated and no approval is required', async () => {
    fetchWallet.mockResolvedValue({ address: '0xwallet' });
    isDelegated.mockResolvedValue(true);

    await expect(resolveSwapNeedsBatch('robinhood', '0-mainnet')).resolves.toBe(false);
  });
});
