import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { ApiCurrencyRates, ApiTokenWithPrice, ApiTransactionType } from '../../api/types';

import { LITECOIN, TONCOIN } from '../../config';
import { pause } from '../../util/schedulers';
import { makeMockTransactionActivity } from '../../../tests/mocks';

import TransactionInfo from '../main/modals/transaction/TransactionInfo';

const mockMountDiamond = jest.fn((_: HTMLCanvasElement) => jest.fn());
jest.mock('../../lib/blue-diamond/diamond', () => ({
  mountDiamond: (canvas: HTMLCanvasElement) => mockMountDiamond(canvas),
}));

const CURRENCY_RATES: ApiCurrencyRates = {
  USD: '1', EUR: '1', RUB: '1', CNY: '1', BTC: '1', TON: '1',
};
const GRAM_TOKEN: ApiTokenWithPrice = { ...TONCOIN, percentChange24h: 0 };
const LITECOIN_TOKEN: ApiTokenWithPrice = { ...LITECOIN, priceUsd: 1, percentChange24h: 0 };

describe('GramDiamond in TransactionInfo', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    mockMountDiamond.mockClear();
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  function render(
    slug: string,
    token: ApiTokenWithPrice,
    { type, noGramDiamond }: { type?: ApiTransactionType; noGramDiamond?: boolean } = {},
  ) {
    const transaction = makeMockTransactionActivity({
      id: 'tx-1',
      amount: 101250000000n,
      fee: 1000n,
      status: 'completed',
      isIncoming: true,
      fromAddress: 'UQAsender',
      toAddress: 'UQArecipient',
      slug,
      type,
    });

    TeactDOM.render(
      <TransactionInfo
        transaction={transaction}
        tokensBySlug={{ [slug]: token }}
        currentAccountId="0-mainnet"
        baseCurrency="USD"
        currencyRates={CURRENCY_RATES}
        theme="light"
        isOpen
        isGramDiamondEnabled={!noGramDiamond}
      />,
      root,
    );
  }

  it('mounts the 3D diamond for a GRAM transfer', async () => {
    render(TONCOIN.slug, GRAM_TOKEN);
    await pause(50);

    const canvas = root.querySelector('canvas');
    expect(canvas).not.toBeNull();
    expect(mockMountDiamond).toHaveBeenCalledTimes(1);
    expect(mockMountDiamond.mock.calls[0][0]).toBe(canvas);
  });

  it('keeps the regular amount when the diamond is off', async () => {
    render(TONCOIN.slug, GRAM_TOKEN, { noGramDiamond: true });
    await pause(50);

    expect(root.querySelector('canvas')).toBeNull();
    expect(mockMountDiamond).not.toHaveBeenCalled();
  });

  it('keeps the regular amount for a typed GRAM transaction', async () => {
    render(TONCOIN.slug, GRAM_TOKEN, { type: 'callContract' });
    await pause(50);

    expect(root.querySelector('canvas')).toBeNull();
    expect(mockMountDiamond).not.toHaveBeenCalled();
  });

  it('renders nothing extra for another token', async () => {
    render(LITECOIN_TOKEN.slug, LITECOIN_TOKEN);
    await pause(50);

    expect(root.querySelector('canvas')).toBeNull();
    expect(root.querySelector('img')).toBeNull();
    expect(mockMountDiamond).not.toHaveBeenCalled();
  });
});
