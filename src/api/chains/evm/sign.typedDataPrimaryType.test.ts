import { verifyTypedData, Wallet } from 'ethers';

import type { UnifiedSignDataPayload } from '../../dappProtocols';
import { ApiCommonError } from '../../types';

import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { signPayload } from './sign';
import { getSignedTypedDataMessage } from './typedDataMessage';

jest.mock('./auth', () => ({
  fetchPrivateKeyString: jest.fn(),
  getSignerFromPrivateKey: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const PERMIT2 = '0x000000000022D473030F116dDEE9F6B43aC78BA3';
const TOKEN = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const DECOY_TOKEN = '0x1111111111111111111111111111111111111111';
const SPENDER = '0x4444444444444444444444444444444444444444';

const wallet = Wallet.createRandom();

const domain = { name: 'Permit2', chainId: 1, verifyingContract: PERMIT2 };
const types = {
  PermitTransferFrom: [
    { name: 'permitted', type: 'TokenPermissions' },
    { name: 'spender', type: 'address' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
  TokenPermissions: [
    { name: 'token', type: 'address' },
    { name: 'amount', type: 'uint256' },
  ],
};
const permit = {
  permitted: { token: TOKEN, amount: '1000000000' },
  spender: SPENDER,
  nonce: '0',
  deadline: '1900000000',
};

function buildTypedData(primaryType: string, message: Record<string, unknown>): UnifiedSignDataPayload {
  return { type: 'eip712', domain, types, primaryType, message } as UnifiedSignDataPayload;
}

beforeEach(() => {
  jest.resetAllMocks();
  jest.mocked(fetchPrivateKeyString).mockResolvedValue(wallet.privateKey);
  jest.mocked(getSignerFromPrivateKey).mockReturnValue(wallet as never);
});

describe('signPayload for typed data naming its primary type', () => {
  it('refuses a nested type shown in place of the struct that gets signed', async () => {
    const payload = buildTypedData('TokenPermissions', { ...permit, token: DECOY_TOKEN, amount: '0' });

    const result = await signPayload('ethereum', ACCOUNT_ID, payload, 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it.each(['EIP712Domain', 'Missing', ''])('refuses primary type %p', async (primaryType) => {
    const result = await signPayload('ethereum', ACCOUNT_ID, buildTypedData(primaryType, permit), 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it('signs the struct its primary type names', async () => {
    const result = await signPayload('ethereum', ACCOUNT_ID, buildTypedData('PermitTransferFrom', permit), 'token');

    expect(verifyTypedData(domain, types, permit, (result as { result: string }).result)).toBe(wallet.address);
  });

  it('signs a message of unusual spelling as the confirmation shows it', async () => {
    const sent = {
      ...permit,
      permitted: { token: TOKEN.toLowerCase(), amount: ' 0x3b9aca00 ', note: 'unsigned' },
      nonce: ' ',
      token: DECOY_TOKEN,
    };
    const shown = getSignedTypedDataMessage(types, 'PermitTransferFrom', sent)!;

    const result = await signPayload('ethereum', ACCOUNT_ID, buildTypedData('PermitTransferFrom', shown), 'token');

    expect(shown).toEqual({ ...permit, permitted: { token: TOKEN.toLowerCase(), amount: '1000000000' } });
    expect(verifyTypedData(domain, types, shown, (result as { result: string }).result)).toBe(wallet.address);
  });

  it.each([
    { verifyingContract: PERMIT2.slice(2) },
    { name: '\udc00' },
    [],
  ])('refuses the domain %p before reading the key', async (sent) => {
    const payload = { ...buildTypedData('PermitTransferFrom', permit), domain: sent } as UnifiedSignDataPayload;

    const result = await signPayload('ethereum', ACCOUNT_ID, payload, 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  it.each(['"__proto__"', '["__proto__"]'])('refuses a field named %s, which signing drops', async (name) => {
    const payload = {
      type: 'eip712',
      domain,
      types: JSON.parse(`{"Permit":[{"name":${name},"type":"bool"},{"name":"value","type":"uint256"}]}`),
      primaryType: 'Permit',
      message: JSON.parse('{"__proto__":false,"value":"1"}'),
    } as UnifiedSignDataPayload;

    const result = await signPayload('ethereum', ACCOUNT_ID, payload, 'token');

    expect(result).toEqual({ error: ApiCommonError.Unexpected });
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });
});
