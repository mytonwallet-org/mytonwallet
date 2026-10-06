import type {
  ApiChain, ApiDappTransfer, ApiNft, ApiNftTransferPayload, ApiParsedPayload, ApiToken,
} from '../../../api/types';
import type { Account, SavedAddress } from '../../../global/types';

import { STON_PTON_SLUG, TONCOIN, TRX } from '../../../config';
import { getDappTransferAssets, getTransferRecipient } from './confirmationHeader';

const USDT: ApiToken = {
  name: 'Tether USD',
  symbol: 'USDT',
  slug: 'ton-usdt',
  decimals: 6,
  chain: 'ton',
};
const TOKENS_BY_SLUG: Record<string, ApiToken> = { [USDT.slug]: USDT };

const ADDRESS = 'UQd9NjAbCdEfGhIjKlMnOpQrStUvWxYz0123456789-5Fa4fK';

function buildTransfer(payload?: ApiParsedPayload, overrides: Partial<ApiDappTransfer> = {}): ApiDappTransfer {
  return {
    chain: 'ton',
    toAddress: ADDRESS,
    amount: 50_000_000n,
    payload,
    isDangerous: false,
    normalizedAddress: ADDRESS,
    displayedToAddress: ADDRESS,
    networkFee: 1_000_000n,
    ...overrides,
  };
}

function buildTokenPayload(slug: string, amount: bigint): ApiParsedPayload {
  return {
    type: 'tokens:transfer',
    queryId: 0n,
    amount,
    destination: ADDRESS,
    responseDestination: ADDRESS,
    forwardAmount: 1n,
    slug,
    tokenAddress: 'token-address',
  };
}

function buildNftPayload(overrides: Partial<ApiNftTransferPayload> = {}): ApiParsedPayload {
  return {
    type: 'nft:transfer',
    queryId: 0n,
    newOwner: ADDRESS,
    responseDestination: ADDRESS,
    forwardAmount: 1n,
    nftAddress: 'nft-address',
    ...overrides,
  };
}

describe('getDappTransferAssets', () => {
  it('takes the token and amount of a jetton transfer from the payload, not the attached native token', () => {
    const transfer = buildTransfer(buildTokenPayload(USDT.slug, 748_210_000n));
    const assets = getDappTransferAssets([transfer], false, TOKENS_BY_SLUG);

    expect(assets).toEqual([{ type: 'token', token: USDT, amount: 748_210_000n }]);
  });

  it('reads non-standard jetton transfers and burns the same way', () => {
    const assets = getDappTransferAssets([
      buildTransfer({
        type: 'tokens:transfer-non-standard', queryId: 0n, amount: 5n, destination: ADDRESS, slug: USDT.slug,
      }),
      buildTransfer({
        type: 'tokens:burn', queryId: 0n, amount: 7n, address: ADDRESS, slug: USDT.slug, isLiquidUnstakeRequest: false,
      }),
    ], false, TOKENS_BY_SLUG);

    expect(assets).toEqual([
      { type: 'token', token: USDT, amount: 5n },
      { type: 'token', token: USDT, amount: 7n },
    ]);
  });

  it('shows a STON.fi pTON transfer as the Toncoin being swapped', () => {
    const assets = getDappTransferAssets([buildTransfer(buildTokenPayload(STON_PTON_SLUG, 3_000_000_000n))], false, {});

    expect(assets).toEqual([{ type: 'token', token: TONCOIN, amount: 3_000_000_000n }]);
  });

  it('keeps the slug and network of a token missing from the token list', () => {
    const [asset] = getDappTransferAssets([buildTransfer(buildTokenPayload('ton-unknown', 1n))], false, {});

    expect(asset).toMatchObject({ type: 'token', token: { slug: 'ton-unknown', chain: 'ton' }, amount: 1n });
  });

  it('shows a message without a token or NFT payload as its native token amount', () => {
    const comment: ApiParsedPayload = { type: 'comment', comment: 'Hi' };
    const storedTrx = { ...TRX, image: 'trx.png' };

    expect(getDappTransferAssets([buildTransfer(comment)], false, {})).toEqual([
      { type: 'token', token: TONCOIN, amount: 50_000_000n },
    ]);
    expect(getDappTransferAssets(
      [buildTransfer(undefined, { chain: 'tron' as ApiChain, amount: 9n })], false, { [TRX.slug]: storedTrx },
    )).toEqual([{ type: 'token', token: storedTrx, amount: 9n }]);
  });

  it('keeps the identity of an NFT with and without metadata', () => {
    const assets = getDappTransferAssets([
      buildTransfer(buildNftPayload({ nftName: 'Durov’s Cap #777' })),
      buildTransfer(buildNftPayload({
        nft: { name: 'Plush Pepe #12', thumbnail: 'pepe.png' } as ApiNft,
      })),
    ], false, TOKENS_BY_SLUG);

    expect(assets).toEqual([
      { type: 'nft', name: 'Durov’s Cap #777', thumbnail: undefined },
      { type: 'nft', name: 'Plush Pepe #12', thumbnail: 'pepe.png' },
    ]);
  });

  it.each([
    ['hidden transfers', [buildTransfer()], true],
    ['a dangerous message', [buildTransfer(), buildTransfer(undefined, { isDangerous: true })], false],
  ])('shows no assets for a request with %s', (_name, transactions, shouldHideTransfers) => {
    expect(getDappTransferAssets(transactions, shouldHideTransfers, TOKENS_BY_SLUG)).toEqual([]);
  });

  it('keeps one asset per message, so the full transfer count is shown', () => {
    const transactions = Array.from({ length: 15 }, () => buildTransfer(buildTokenPayload(USDT.slug, 1n)));

    expect(getDappTransferAssets(transactions, false, TOKENS_BY_SLUG)).toHaveLength(15);
  });
});

describe('getTransferRecipient', () => {
  const OTHER_ADDRESS = 'UQotherAccountAddress000000000000000000000000000';
  const accounts = {
    'current-mainnet': { title: 'Current', type: 'mnemonic', byChain: { ton: { address: ADDRESS } } },
    'other-mainnet': { title: 'Savings', type: 'mnemonic', byChain: { ton: { address: OTHER_ADDRESS } } },
  } as unknown as Record<string, Account>;
  const savedAddresses: SavedAddress[] = [
    { name: 'Pavel Durov', address: ADDRESS, chain: 'ton' },
  ];

  it('names the user’s other account and passes its id for the avatar', () => {
    expect(getTransferRecipient({
      address: OTHER_ADDRESS, chain: 'ton', currentAccountId: 'current-mainnet', accounts,
    })).toEqual({ type: 'wallet', name: 'Savings', accountId: 'other-mainnet', imageUrl: undefined });
  });

  it('skips the current account and falls back to a saved address', () => {
    expect(getTransferRecipient({
      address: ADDRESS, chain: 'ton', currentAccountId: 'current-mainnet', accounts, savedAddresses,
    })).toEqual({ type: 'wallet', name: 'Pavel Durov' });
  });

  it('does not match a saved address from another network', () => {
    expect(getTransferRecipient({
      address: ADDRESS, chain: 'tron' as ApiChain, currentAccountId: 'current-mainnet', savedAddresses,
    })).toEqual({ type: 'address', text: 'UQd9Nj···5Fa4fK' });
  });

  it('shows the domain as text', () => {
    expect(getTransferRecipient({
      address: ADDRESS, addressName: 'durov.ton', chain: 'ton', currentAccountId: 'current-mainnet',
    })).toEqual({ type: 'address', text: 'durov.ton' });
  });
});
