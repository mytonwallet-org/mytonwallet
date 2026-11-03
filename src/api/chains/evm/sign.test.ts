import type { UnifiedSignDataPayload } from '../../dappProtocols';
import { ApiCommonError } from '../../types';

import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { signPayload } from './sign';

jest.mock('./auth', () => ({
  fetchPrivateKeyString: jest.fn(),
  getSignerFromPrivateKey: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const SIGNATURE = '0xsignature';

const signTypedData = jest.fn();

function typedData(chainId?: unknown): UnifiedSignDataPayload {
  return {
    type: 'eip712',
    domain: {
      name: 'Token',
      version: '1',
      ...(chainId === undefined ? {} : { chainId }),
      verifyingContract: '0x3333333333333333333333333333333333333333',
    },
    types: {
      Permit: [
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
      ],
    },
    primaryType: 'Permit',
    message: { spender: '0x4444444444444444444444444444444444444444', value: '1' },
  } as UnifiedSignDataPayload;
}

beforeEach(() => {
  jest.resetAllMocks();
  signTypedData.mockResolvedValue(SIGNATURE);
  jest.mocked(fetchPrivateKeyString).mockResolvedValue('0xkey');
  jest.mocked(getSignerFromPrivateKey).mockReturnValue({ signTypedData } as never);
});

describe('signPayload for typed data', () => {
  it.each([8453, '8453', '0x2105'])('refuses domain chainId %p on Ethereum mainnet', async (chainId) => {
    const result = await signPayload('ethereum', ACCOUNT_ID, typedData(chainId), 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(signTypedData).not.toHaveBeenCalled();
  });

  it.each([1, '1', '0x1', 1n, undefined])('signs domain chainId %p on Ethereum mainnet', async (chainId) => {
    const result = await signPayload('ethereum', ACCOUNT_ID, typedData(chainId), 'token');

    expect(result).toEqual({ result: SIGNATURE });
    expect(signTypedData).toHaveBeenCalledTimes(1);
  });
});

describe('signPayload for typed data carrying its network', () => {
  function testnetTypedData(chainId: number): UnifiedSignDataPayload {
    return { ...typedData(chainId), network: 'testnet' } as UnifiedSignDataPayload;
  }

  it('signs the testnet chain id for a mainnet account', async () => {
    const result = await signPayload('base', ACCOUNT_ID, testnetTypedData(84532), 'token');

    expect(result).toEqual({ result: SIGNATURE });
  });

  it('refuses the mainnet chain id for a testnet account despite the payload network', async () => {
    const payload = { ...typedData(8453), network: 'mainnet' } as UnifiedSignDataPayload;
    const result = await signPayload('base', '0-testnet', payload, 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it('refuses the mainnet chain id', async () => {
    const result = await signPayload('base', ACCOUNT_ID, testnetTypedData(8453), 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(signTypedData).not.toHaveBeenCalled();
  });
});
