import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';

import type { ApiCurrencyRates, ApiTokenWithPrice } from '../../../../api/types';

import { TRC20_USDT_MAINNET } from '../../../../config';
import { pause } from '../../../../util/schedulers';
import { makeMockTransactionActivity } from '../../../../../tests/mocks';

import Transaction from './Transaction';

const MAX_UINT256 = 2n ** 256n - 1n;
const CURRENCY_RATES: ApiCurrencyRates = {
  USD: '1',
  EUR: '1',
  RUB: '1',
  CNY: '1',
  BTC: '1',
  TON: '1',
};
const TOKEN: ApiTokenWithPrice = {
  ...TRC20_USDT_MAINNET,
  priceUsd: 1,
  percentChange24h: 0,
};

describe('Transaction approval display', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('renders an unlimited approval without transfer signs or fiat value', async () => {
    const transaction = makeMockTransactionActivity({
      id: 'approval-tx',
      type: 'approval',
      amount: MAX_UINT256,
      isApprovalUnlimited: true,
      isIncoming: true,
      fromAddress: 'TKk2k4trTUSksCiA3k8Aq5WAsUo3b8FCKj',
      toAddress: 'TPwezUWpEGmFBENNWJHwXHRG1D2NCEEt5s',
      slug: TOKEN.slug,
    });

    TeactDOM.render(
      <Transaction
        tokensBySlug={{ [TOKEN.slug]: TOKEN }}
        transaction={transaction}
        annualYield={undefined}
        yieldType={undefined}
        appTheme="light"
        savedAddresses={undefined}
        accounts={undefined}
        currentAccountId="tron-mainnet-0"
        baseCurrency="USD"
        currencyRates={CURRENCY_RATES}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('Token Approval');
    expect(root.textContent).toContain('∞ USDT');
    expect(root.textContent).not.toContain('Unlimited');
    expect(root.textContent).not.toContain(MAX_UINT256.toString());
    expect(root.textContent).not.toContain('$');
    expect(root.textContent).not.toContain('+');
  });
});
