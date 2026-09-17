import type { ApiAccountWithChain } from '../../../types';
import { ApiCommonError } from '../../../types';

import { signTonProofWithPrivateKey } from '../../../dappProtocols/adapters/tonConnect/signing';
import { fetchPrivateKey } from '../auth';
import { getSigner } from './signer';

jest.mock('../auth');
jest.mock('../../../dappProtocols/adapters/tonConnect/signing');

const ADDRESS = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const ENCLAVE_TOKEN = 'enclave-token';

const account = {
  type: 'mnemonic',
  byChain: { ton: { address: ADDRESS, version: 'W5', publicKey: '00'.repeat(32) } },
} as unknown as ApiAccountWithChain<'ton'>;

const proof = { timestamp: 0, domain: { lengthBytes: 0, value: '' }, payload: '' } as any;

function buildSigner() {
  return getSigner('ton-mainnet-1', account, ENCLAVE_TOKEN);
}

describe('mnemonic signer key reads', () => {
  beforeEach(() => {
    jest.mocked(fetchPrivateKey).mockResolvedValue(new Uint8Array(64));
    jest.mocked(signTonProofWithPrivateKey).mockResolvedValue(new Uint8Array(64));
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  // Each read spends an Enclave session usage, so a caller that ends up not signing - an operation
  // that fails while preparing, or a batch that turns out to be empty - must not cost the session.
  it('reads nothing until something is signed', () => {
    buildSigner();

    expect(fetchPrivateKey).not.toHaveBeenCalled();
  });

  // A single operation may sign several times, and the session grants one read by default, so every
  // signature after the first has to reuse the key rather than ask for it again.
  it('reads the key once however many signatures it produces', async () => {
    const signer = buildSigner();

    await signer.signTonProof(proof);
    await signer.signTonProof(proof);

    expect(fetchPrivateKey).toHaveBeenCalledTimes(1);
  });

  // Concurrent signatures share the in-flight read rather than racing into two of them.
  it('reads the key once when signatures overlap', async () => {
    const signer = buildSigner();

    await Promise.all([signer.signTonProof(proof), signer.signTonProof(proof)]);

    expect(fetchPrivateKey).toHaveBeenCalledTimes(1);
  });

  // A dead or wrong session yields no key; the caller learns about it as a returned error rather
  // than as a rejection, because that is how every other expected signing failure travels.
  it('reports an unreadable key as a wrong password', async () => {
    jest.mocked(fetchPrivateKey).mockResolvedValue(undefined);
    const signer = buildSigner();

    await expect(signer.signTonProof(proof)).resolves.toEqual({ error: ApiCommonError.InvalidPassword });
  });
});
