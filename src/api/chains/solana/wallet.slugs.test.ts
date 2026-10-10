import { fetchJson } from '../../../util/fetch';
import { getTokenBySlug } from '../../common/tokens';
import { fetchAccountAssets } from './wallet';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));
jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));
jest.mock('../../db', () => ({
  tokenRepository: {
    all: jest.fn().mockResolvedValue([]),
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));

const WALLET_ADDRESS = 'So1anaWa11et1111111111111111111111111111111';
// The mints share their first 10 characters, which make the backend slug
const MINT = 'VanityMintAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const OTHER_MINT = 'VanityMintBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const SLUG = 'solana-vanitymint';
const OTHER_SLUG = `solana-${OTHER_MINT.toLowerCase()}`;

describe('Solana token slugs', () => {
  it('gives each of the mints found together a slug of its own', async () => {
    jest.mocked(fetchJson).mockResolvedValueOnce({
      result: {
        items: [buildItem(MINT, 'ONE', 5), buildItem(OTHER_MINT, 'TWO', 7)],
        nativeBalance: { lamports: 0, price_per_sol: 0, total_price: 0 },
      },
    });

    const balances = await fetchAccountAssets('mainnet', WALLET_ADDRESS, jest.fn());

    expect(balances).toEqual(expect.objectContaining({ [SLUG]: 5n, [OTHER_SLUG]: 7n }));
    expect(getTokenBySlug(SLUG)).toMatchObject({ tokenAddress: MINT, symbol: 'ONE' });
    expect(getTokenBySlug(OTHER_SLUG)).toMatchObject({ tokenAddress: OTHER_MINT, symbol: 'TWO' });
  });
});

function buildItem(id: string, symbol: string, balance: number) {
  return {
    id,
    content: { metadata: { name: symbol, symbol }, files: [], links: {} },
    token_info: { balance, decimals: 6, token_program: '', associated_token_address: '' },
  };
}
