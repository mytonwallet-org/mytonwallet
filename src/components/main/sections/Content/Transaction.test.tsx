import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';

import type { ApiCurrencyRates, ApiTokenWithPrice } from '../../../../api/types';

import { LITECOIN, TRC20_USDT_MAINNET } from '../../../../config';
import { pause } from '../../../../util/schedulers';
import { makeMockTransactionActivity } from '../../../../../tests/mocks';

import Transaction from './Transaction';

jest.mock('../../../../lib/rlottie/RLottie.async', () => {
  const animation = {
    changeData: jest.fn(),
    goToFirstFrame: jest.fn(),
    isPlaying: jest.fn(() => false),
    pause: jest.fn(),
    play: jest.fn(),
    playSegment: jest.fn(),
    removeView: jest.fn(),
    setColor: jest.fn(),
    setNoLoop: jest.fn(),
    setSharedCanvasCoords: jest.fn(),
    setSpeed: jest.fn(),
  };

  return {
    ensureRLottie: jest.fn(() => Promise.resolve({ init: jest.fn(() => animation) })),
    getRLottie: jest.fn(() => ({ init: jest.fn(() => animation) })),
  };
});

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

  it('keeps UTXO confirmation progress out of the transaction row', async () => {
    const litecoinToken: ApiTokenWithPrice = {
      ...LITECOIN,
      priceUsd: 1,
      percentChange24h: 0,
    };
    const transaction = makeMockTransactionActivity({
      id: 'ltc-tx',
      amount: 100000n,
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 600,
      status: 'pending',
      isIncoming: true,
      fromAddress: 'ltc1qsender0000000000000000000000000000000',
      toAddress: 'ltc1qvmw9dmensxtuxu5vw7mxtxqurad2u99m9cqgtp',
      slug: litecoinToken.slug,
    });

    TeactDOM.render(
      <Transaction
        tokensBySlug={{ [litecoinToken.slug]: litecoinToken }}
        transaction={transaction}
        annualYield={undefined}
        yieldType={undefined}
        appTheme="light"
        savedAddresses={undefined}
        accounts={undefined}
        currentAccountId="0-mainnet"
        baseCurrency="USD"
        currencyRates={CURRENCY_RATES}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).not.toContain('1/2');
    expect(root.textContent).not.toContain('~10m');
    expect(root.textContent).not.toContain('2/2');
  });
});
