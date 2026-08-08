const mockCallBackendPost = jest.fn();

jest.mock('../common/backend', () => ({
  callBackendPost: (...args: unknown[]) => mockCallBackendPost(...args),
}));

import { reportNft } from './nfts';

describe('NFT methods', () => {
  afterEach(() => {
    mockCallBackendPost.mockReset();
  });

  it('sends a chain-qualified NFT report to the backend', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const options = {
      chain: 'ton' as const,
      network: 'mainnet' as const,
      nftAddress: 'EQ-reported-nft',
    };

    await reportNft(options);

    expect(mockCallBackendPost).toHaveBeenCalledWith('/nfts/report', options);
  });
});
