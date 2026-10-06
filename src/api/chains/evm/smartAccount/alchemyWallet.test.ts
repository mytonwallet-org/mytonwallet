import { concat, getBytes, keccak256, toUtf8Bytes, Wallet } from 'ethers';

import {
  type AlchemyPrepareCallsResult,
  estimateMaxCostFromPrepareResult,
  signAlchemyPreparedCalls,
} from './alchemyWallet';

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

describe('signAlchemyPreparedCalls', () => {
  it('signs a single prepared user operation', async () => {
    const wallet = Wallet.createRandom();
    const prepareResult: AlchemyPrepareCallsResult = {
      type: 'user-operation-v070',
      chainId: '0xaa36a7',
      data: {
        sender: wallet.address,
        nonce: '0x1',
        callData: '0x',
      },
      signatureRequest: {
        type: 'personal_sign',
        data: {
          raw: '0x' + '11'.repeat(32),
        },
      },
    };

    const signed = await signAlchemyPreparedCalls(prepareResult, wallet.privateKey, 'mainnet');

    expect(signed.type).toBe('user-operation-v070');
    expect('signature' in signed && signed.signature.data).toMatch(/^0x/i);
  });

  it('signs a prepared array with eip7702Auth and personal_sign requests', async () => {
    const wallet = Wallet.createRandom();
    const prepareResult: AlchemyPrepareCallsResult = {
      type: 'array',
      data: [
        {
          type: 'eip7702-auth',
          data: {
            address: '0x690077893755a5e9232678e3255a62b755c728f5',
            nonce: '0x0',
          },
          chainId: '0x1',
          signatureRequest: {
            type: 'eip7702Auth',
            rawPayload: '0x' + '22'.repeat(32),
          },
        },
        {
          type: 'user-operation-v070',
          data: {
            sender: wallet.address,
            nonce: '0x1',
            callData: '0x',
          },
          chainId: '0x1',
          signatureRequest: {
            type: 'personal_sign',
            data: {
              raw: '0x' + '11'.repeat(32),
            },
            rawPayload: '0x' + '33'.repeat(32),
          },
        },
      ],
    };

    const signed = await signAlchemyPreparedCalls(prepareResult, wallet.privateKey, 'mainnet');

    expect(signed.type).toBe('array');
    if (signed.type !== 'array') {
      throw new Error('Expected array signed calls');
    }

    expect(signed.data).toHaveLength(2);
    expect((signed.data as any)[0].signature?.data).toMatch(/^0x/i);
    expect((signed.data as any)[1].signature?.data).toMatch(/^0x/i);
  });

  it('signs eth_signTypedData_v4 signature requests', async () => {
    const wallet = Wallet.createRandom();
    const prepareResult: AlchemyPrepareCallsResult = {
      type: 'user-operation-v070',
      chainId: '0x1',
      data: {
        sender: wallet.address,
        nonce: '0x1',
        callData: '0x',
      },
      signatureRequest: {
        type: 'eth_signTypedData_v4',
        data: {
          domain: {
            name: 'Test',
            version: '1',
            chainId: 1,
            verifyingContract: wallet.address,
          },
          types: {
            EIP712Domain: [
              { name: 'name', type: 'string' },
              { name: 'version', type: 'string' },
              { name: 'chainId', type: 'uint256' },
              { name: 'verifyingContract', type: 'address' },
            ],
            Mail: [
              { name: 'contents', type: 'string' },
            ],
          },
          primaryType: 'Mail',
          message: {
            contents: 'hello',
          },
        },
      },
    };

    const signed = await signAlchemyPreparedCalls(prepareResult, wallet.privateKey, 'mainnet');
    const expectedSignature = await wallet.signTypedData(
      (prepareResult.signatureRequest!.data! as any).domain,
      { Mail: (prepareResult.signatureRequest!.data! as any).types.Mail },
      (prepareResult.signatureRequest!.data! as any).message,
    );

    expect('signature' in signed && signed.signature.data).toBe(expectedSignature);
  });

  it('uses data.raw for personal_sign when both raw and rawPayload are present', async () => {
    const wallet = Wallet.createRandom();
    const dataRaw = `0x${'11'.repeat(32)}`;
    const rawPayload = keccak256(concat([
      toUtf8Bytes('\x19Ethereum Signed Message:\n32'),
      getBytes(dataRaw),
    ]));

    const prepareResult: AlchemyPrepareCallsResult = {
      type: 'user-operation-v070',
      chainId: '0x1',
      data: {
        sender: wallet.address,
        nonce: '0x1',
        callData: '0x',
      },
      signatureRequest: {
        type: 'personal_sign',
        data: { raw: dataRaw },
        rawPayload,
      },
    };

    const signed = await signAlchemyPreparedCalls(prepareResult, wallet.privateKey, 'mainnet');
    const expectedSignature = await wallet.signMessage(getBytes(dataRaw));

    expect('signature' in signed && signed.signature.data).toBe(expectedSignature);
  });
});
