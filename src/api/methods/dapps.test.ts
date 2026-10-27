import type { StoredSessionChain } from '../dappProtocols/storage';
import type { DappProofRequest } from '../dappProtocols/types';
import { ApiCommonError } from '../types';

import chains from '../chains';
import { signDappProof } from './dapps';

jest.mock('../chains', () => ({
  __esModule: true,
  default: { ton: { dapp: { signConnectionProof: jest.fn() } }, solana: {} },
}));

const mockSignConnectionProof = jest.mocked(chains.ton.dapp!.signConnectionProof!);
const tonChain: StoredSessionChain = { chain: 'ton', address: 'test-address', network: 'mainnet' };
const proof: DappProofRequest = {
  type: 'tonProof', timestamp: 1787684690, domain: 'fragment.com', payload: 'test-proof',
};
const signature = Buffer.alloc(64, 1).toString('base64');

describe('signDappProof', () => {
  beforeEach(() => {
    mockSignConnectionProof.mockReset();
  });

  it('preserves signer errors instead of returning empty signatures', async () => {
    mockSignConnectionProof.mockResolvedValue({ error: ApiCommonError.InvalidPassword });

    await expect(signDappProof([tonChain], '0-mainnet', proof, 'token')).resolves.toEqual({
      error: ApiCommonError.InvalidPassword,
    });
  });

  it('does not return partial signatures when a later signer fails', async () => {
    mockSignConnectionProof
      .mockResolvedValueOnce({ signature, publicKey: 'public-key' })
      .mockResolvedValueOnce({ error: ApiCommonError.InvalidPassword });

    await expect(signDappProof([tonChain, tonChain], '0-mainnet', proof, 'token')).resolves.toEqual({
      error: ApiCommonError.InvalidPassword,
    });
  });

  it.each([
    { name: 'no requested chains', requestedChains: [] },
    { name: 'an unsupported signer', requestedChains: [{ ...tonChain, chain: 'solana' as const }] },
    { name: 'a missing signing result', requestedChains: [tonChain] },
  ])('rejects $name', async ({ requestedChains }) => {
    await expect(signDappProof(requestedChains, '0-mainnet', proof, 'token')).resolves.toEqual({
      error: ApiCommonError.Unexpected,
    });
  });

  it('rejects an empty signature', async () => {
    mockSignConnectionProof.mockResolvedValue({ signature: '', publicKey: 'public-key' });

    await expect(signDappProof([tonChain], '0-mainnet', proof, 'token')).resolves.toEqual({
      error: ApiCommonError.Unexpected,
    });
  });

  it('returns signatures and their public keys on success', async () => {
    mockSignConnectionProof.mockResolvedValue({ signature, publicKey: 'public-key' });

    await expect(signDappProof([tonChain], '0-mainnet', proof, 'token')).resolves.toEqual({
      signatures: [signature], publicKeys: ['public-key'],
    });
    expect(mockSignConnectionProof).toHaveBeenCalledWith('0-mainnet', proof, 'token');
  });
});
