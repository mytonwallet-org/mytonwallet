import {
  getBytes,
  hashAuthorization,
  hashMessage,
  Interface,
  recoverAddress,
  verifyMessage,
  Wallet,
} from 'ethers';

import type { AlchemyPrepareCallsResult, AlchemyPreparedCallItem, AlchemyPreparedCallsBinding } from './alchemyWallet';
import type { EvmMetaTransaction } from './types';
import type { UserOperationV07Data } from './userOperation';

import {
  estimateMaxCostFromPrepareResult,
  signAlchemyPreparedCalls,
} from './alchemyWallet';
import { ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS } from './constants';
import { hashUserOperationV07, isModularAccountCallData } from './userOperation';

// A live `wallet_prepareCalls` answer on Base for a fresh EOA batching two calls.
const BASE_PREPARED_AUTHORIZATION = {
  type: 'authorization',
  data: { address: '0x77021100bD87b7008E5E1989d0eB38555d0d0000', nonce: '0x0' },
  chainId: '0x2105',
  signatureRequest: {
    type: 'eip7702Auth' as const,
    rawPayload: '0xf03e3bc5dc7990ca51a41060478e87677bef5cb11192aa46d97fb6f1c261d626',
  },
};

const BASE_PREPARED_USER_OPERATION = {
  type: 'user-operation-v070',
  data: {
    sender: '0xFad818EBe50790749d530E9743045a5740796100',
    nonce: '0x10000000000000000',
    callData: '0x34fcd5be'
      + '0000000000000000000000000000000000000000000000000000000000000020'
      + '0000000000000000000000000000000000000000000000000000000000000002'
      + '0000000000000000000000000000000000000000000000000000000000000040'
      + '00000000000000000000000000000000000000000000000000000000000000c0'
      + '000000000000000000000000000000000000000000000000000000000000dead'
      + '0000000000000000000000000000000000000000000000000000000000000000'
      + '0000000000000000000000000000000000000000000000000000000000000060'
      + '0000000000000000000000000000000000000000000000000000000000000000'
      + '000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913'
      + '0000000000000000000000000000000000000000000000000000000000000000'
      + '0000000000000000000000000000000000000000000000000000000000000060'
      + '0000000000000000000000000000000000000000000000000000000000000044'
      + '095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b4'
      + '3ac78ba300000000000000000000000000000000000000000000000000000000'
      + '0000000100000000000000000000000000000000000000000000000000000000',
    callGasLimit: '0xbea9',
    verificationGasLimit: '0x15495',
    preVerificationGas: '0x11b4c',
    maxFeePerGas: '0xa52d28',
    maxPriorityFeePerGas: '0x16e360',
  },
  chainId: '0x2105',
  signatureRequest: {
    type: 'personal_sign' as const,
    data: { raw: '0x343819eece56691f2745c1062f4cf19638b9c0dcc4f1463fc1fc357fe21d7c48' },
    rawPayload: '0x5df728eebf470fde13e621a1b80f7c4fbeb4286661e9446850cfdd6fc2a3692c',
  },
};

const BASE_CALLS: EvmMetaTransaction[] = [
  { to: '0x000000000000000000000000000000000000dEaD', value: 0n, data: '0x' },
  {
    to: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    value: 0n,
    data: '0x095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3'
      + '0000000000000000000000000000000000000000000000000000000000000001',
  },
];

const CHAIN_ID = 8453n;
const ALCHEMY_DELEGATE = BASE_PREPARED_AUTHORIZATION.data.address;
const HOSTILE_ADDRESS = '0x00000000000000000000000000000000DeaDBeef';
const ALCHEMY_V1_0_DELEGATE = '0x69007702764179f14f51cdce752f4f775d74e139';
const modularAccountInterface = new Interface([
  'function executeBatch((address target, uint256 value, bytes data)[] calls)',
]);

function encodeCalls(calls: EvmMetaTransaction[]) {
  return modularAccountInterface.encodeFunctionData('executeBatch', [
    calls.map(({ to, value = 0n, data = '0x' }) => [to, value, data]),
  ]);
}

function buildPreparedCalls(wallet: { address: string }, calls = BASE_CALLS) {
  const userOperation = {
    ...BASE_PREPARED_USER_OPERATION.data,
    sender: wallet.address,
    callData: encodeCalls(calls),
  };
  const userOperationHash = hashUserOperationV07(userOperation, CHAIN_ID);

  const authorization: AlchemyPreparedCallItem = {
    ...BASE_PREPARED_AUTHORIZATION,
    signatureRequest: {
      type: 'eip7702Auth',
      rawPayload: hashAuthorization({ address: ALCHEMY_DELEGATE, nonce: 0n, chainId: CHAIN_ID }),
    },
  };
  const operation: AlchemyPreparedCallItem = {
    type: 'user-operation-v070',
    data: userOperation,
    chainId: BASE_PREPARED_USER_OPERATION.chainId,
    signatureRequest: {
      type: 'personal_sign',
      data: { raw: userOperationHash },
      rawPayload: hashMessage(getBytes(userOperationHash)),
    },
  };

  return { authorization, operation, userOperationHash };
}

function bindTo(wallet: { address: string }, calls = BASE_CALLS): AlchemyPreparedCallsBinding {
  return { chainId: CHAIN_ID, sender: wallet.address, calls, delegate: ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS };
}

function withOperationData(operation: AlchemyPreparedCallItem, patch: Record<string, string>): AlchemyPreparedCallItem {
  const data = { ...operation.data, ...patch };

  const raw = hashUserOperationV07(data as UserOperationV07Data, CHAIN_ID);

  return { ...operation, data, signatureRequest: { type: 'personal_sign', data: { raw } } };
}

describe('estimateMaxCostFromPrepareResult', () => {
  it('computes max gas cost from a single user operation response', () => {
    const prepareResult: AlchemyPrepareCallsResult = {
      type: 'user-operation-v070',
      chainId: '0xaa36a7',
      data: {
        maxFeePerGas: '0x2',
        callGasLimit: '0x3',
        verificationGasLimit: '0x4',
        preVerificationGas: '0x5',
      },
    };

    expect(estimateMaxCostFromPrepareResult(prepareResult)).toBe(24n);
  });
});

describe('local digests', () => {
  it('reproduces the user operation hash Alchemy returned on Base', () => {
    expect(hashUserOperationV07(BASE_PREPARED_USER_OPERATION.data, CHAIN_ID))
      .toBe(BASE_PREPARED_USER_OPERATION.signatureRequest.data.raw);
  });

  it('reproduces the EIP-7702 authorization digest Alchemy returned on Base', () => {
    expect(hashAuthorization({ address: ALCHEMY_DELEGATE, nonce: 0n, chainId: CHAIN_ID }))
      .toBe(BASE_PREPARED_AUTHORIZATION.signatureRequest.rawPayload);
  });

  it('matches the executeBatch calls Alchemy encoded on Base', () => {
    expect(isModularAccountCallData(BASE_PREPARED_USER_OPERATION.data.callData, BASE_CALLS)).toBe(true);
  });

  it('delegates to the contract the prepare request asks for', () => {
    expect(ALCHEMY_DELEGATE.toLowerCase()).toBe(ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS);
  });
});

describe('signAlchemyPreparedCalls', () => {
  const wallet = Wallet.createRandom();

  it('signs the locally computed authorization and user operation digests', async () => {
    const { authorization, operation, userOperationHash } = buildPreparedCalls(wallet);

    const signed = await signAlchemyPreparedCalls(
      { type: 'array', data: [authorization, operation] },
      wallet.privateKey,
      bindTo(wallet),
    );

    if (signed.type !== 'array') throw new Error('Expected array signed calls');
    const [authorizationSignature, operationSignature] = (signed.data as AlchemyPreparedCallItem[])
      .map((item) => item.signature!.data);

    expect(recoverAddress(authorization.signatureRequest!.rawPayload!, authorizationSignature)).toBe(wallet.address);
    expect(verifyMessage(getBytes(userOperationHash), operationSignature)).toBe(wallet.address);
  });

  it('signs its own authorization digest whatever raw payload the response carries', async () => {
    const { authorization, operation } = buildPreparedCalls(wallet);
    const localDigest = authorization.signatureRequest!.rawPayload!;

    const tampered: AlchemyPreparedCallItem = {
      ...authorization,
      signatureRequest: { type: 'eip7702Auth', rawPayload: `0x${'22'.repeat(32)}` },
    };
    const signed = await signAlchemyPreparedCalls(
      { type: 'array', data: [tampered, operation] },
      wallet.privateKey,
      bindTo(wallet),
    );

    const [authorizationSignature] = (signed.data as AlchemyPreparedCallItem[]).map((item) => item.signature!.data);
    expect(recoverAddress(localDigest, authorizationSignature)).toBe(wallet.address);
  });

  it('signs a single user operation of an already delegated account', async () => {
    const { operation, userOperationHash } = buildPreparedCalls(wallet);

    const signed = await signAlchemyPreparedCalls(
      { ...operation, signatureRequest: operation.signatureRequest },
      wallet.privateKey,
      bindTo(wallet),
    );

    expect('signature' in signed && verifyMessage(getBytes(userOperationHash), signed.signature.data))
      .toBe(wallet.address);
  });

  it('accepts a single call encoded as execute', async () => {
    const calls = [BASE_CALLS[1]];
    const { operation } = buildPreparedCalls(wallet, calls);
    const callData = new Interface(['function execute(address target, uint256 value, bytes data)'])
      .encodeFunctionData('execute', [calls[0].to, 0n, calls[0].data]);

    const prepared = withOperationData(operation, { callData });

    await expect(signAlchemyPreparedCalls(prepared, wallet.privateKey, bindTo(wallet, calls)))
      .resolves.toHaveProperty('signature');
  });

  describe('refuses a prepared response that does not match the requested calls', () => {
    function signItems(items: AlchemyPreparedCallItem[]) {
      return signAlchemyPreparedCalls({ type: 'array', data: items }, wallet.privateKey, bindTo(wallet));
    }

    it.each([
      ['an unknown contract', HOSTILE_ADDRESS],
      ['the older Alchemy delegate', ALCHEMY_V1_0_DELEGATE],
    ])('when the authorization delegates to %s', async (_, address) => {
      const { authorization, operation } = buildPreparedCalls(wallet);
      const rawPayload = hashAuthorization({ address, nonce: 0n, chainId: CHAIN_ID });

      await expect(signItems([{
        ...authorization,
        data: { ...authorization.data, address },
        signatureRequest: { type: 'eip7702Auth', rawPayload },
      }, operation])).rejects.toThrow('did not request');
    });

    it('when the response delegates an account the request did not ask to delegate', async () => {
      const { authorization, operation } = buildPreparedCalls(wallet);

      await expect(signAlchemyPreparedCalls(
        { type: 'array', data: [authorization, operation] },
        wallet.privateKey,
        { ...bindTo(wallet), delegate: undefined },
      )).rejects.toThrow('did not request');
    });

    it.each([
      ['names a paymaster', { paymaster: HOSTILE_ADDRESS, paymasterData: '0x12' }, 'paymaster'],
      ['carries an init call', { factory: HOSTILE_ADDRESS, factoryData: '0x12' }, 'init call'],
      ['selects a validation other than the account key', {
        nonce: `0x${(2n << 64n).toString(16)}`,
      }, 'another validation'],
    ])('when the user operation %s', async (_, patch, message) => {
      const { authorization, operation } = buildPreparedCalls(wallet);

      await expect(signItems([authorization, withOperationData(operation, patch)])).rejects.toThrow(message);
    });

    it('when the authorization is valid on every chain', async () => {
      const { authorization, operation } = buildPreparedCalls(wallet);

      await expect(signItems([{ ...authorization, chainId: '0x0' }, operation])).rejects.toThrow('another chain');
    });

    it('when the user operation calls another contract', async () => {
      const { authorization, operation } = buildPreparedCalls(wallet, [
        ...BASE_CALLS,
        { to: HOSTILE_ADDRESS, value: 1n, data: '0x' },
      ]);

      await expect(signItems([authorization, operation])).rejects.toThrow('differ from the requested calls');
    });

    it('when the user operation belongs to another sender', async () => {
      const { authorization, operation } = buildPreparedCalls(Wallet.createRandom());

      await expect(signItems([authorization, operation])).rejects.toThrow('another sender');
    });

    it.each([
      ['the digest is not the one computed from its fields', {
        type: 'personal_sign', data: { raw: `0x${'11'.repeat(32)}` },
      }, 'does not match'],
      ['the response asks for typed data', {
        type: 'eth_signTypedData_v4', data: { domain: {}, types: {}, primaryType: 'Mail', message: {} },
      }, 'unexpected signature request'],
    ] as const)('when %s', async (_, signatureRequest, message) => {
      const { authorization, operation } = buildPreparedCalls(wallet);

      await expect(signItems([authorization, { ...operation, signatureRequest }])).rejects.toThrow(message);
    });

    it('when the response holds a second user operation with the same calls', async () => {
      const { authorization, operation } = buildPreparedCalls(wallet);
      const replay = withOperationData(operation, { nonce: `0x${((1n << 64n) + 1n).toString(16)}` });

      await expect(signItems([authorization, operation, replay])).rejects.toThrow('one user operation');
    });

    it('when the response holds an unknown item', async () => {
      const { authorization, operation } = buildPreparedCalls(wallet);

      await expect(signItems([{ ...authorization, type: 'paymaster-permit' }, operation]))
        .rejects.toThrow('Unsupported Alchemy prepared call type');
    });
  });
});
