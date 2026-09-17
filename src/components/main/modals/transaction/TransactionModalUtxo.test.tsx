import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';

import type { ApiCurrencyRates, ApiTokenWithPrice } from '../../../../api/types';
import type { LangFn } from '../../../../hooks/useLang';

import { LITECOIN } from '../../../../config';
import { getTranslation } from '../../../../util/langProvider';
import { pause } from '../../../../util/schedulers';
import { makeMockTransactionActivity } from '../../../../../tests/mocks';

import TransactionHeader from '../../../common/TransactionHeader';
import TransactionInfo, { formatUtxoEtaForModal } from './TransactionInfo';

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

const CURRENCY_RATES: ApiCurrencyRates = {
  USD: '1',
  EUR: '1',
  RUB: '1',
  CNY: '1',
  BTC: '1',
  TON: '1',
};
const LITECOIN_TOKEN: ApiTokenWithPrice = {
  ...LITECOIN,
  priceUsd: 1,
  percentChange24h: 0,
};

describe('UTXO transaction modal confirmations', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows the pending confirmation count in the modal header subtitle', async () => {
    const transaction = makeMockTransactionActivity({
      id: 'ltc-tx',
      slug: LITECOIN_TOKEN.slug,
      confirmations: 0,
      maxConfirmations: 2,
      status: 'pending',
      isIncoming: false,
      fromAddress: 'ltc1qsender0000000000000000000000000000000',
      toAddress: 'ltc1qvmw9dmensxtuxu5vw7mxtxqurad2u99m9cqgtp',
    });

    TeactDOM.render(
      <TransactionHeader
        transaction={transaction}
        appTheme="light"
        onClose={jest.fn()}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('0 of 2 confirmations');
  });

  it('formats ETA through localized duration and wrapper keys', () => {
    const calls: Array<{ key: string; value?: string | number; pluralValue?: number }> = [];
    const lang = ((key: string, value?: string | number, _format?: 'i', pluralValue?: number) => {
      calls.push({ key, value, pluralValue });
      if (key === 'minute') return `${value} minutes`;
      if (key === '$utxo_estimated_time') return `~ ${value}`;
      return key;
    }) as LangFn;

    expect(formatUtxoEtaForModal(getTranslation, 60)).toBe('~ 1 minute');
    expect(formatUtxoEtaForModal(lang, 20 * 60)).toBe('~ 20 minutes');
    expect(calls).toEqual([
      { key: 'minute', value: 20, pluralValue: 20 },
      { key: '$utxo_estimated_time', value: '20 minutes', pluralValue: undefined },
    ]);
  });

  it('shows estimated time in modal details before the fee row', async () => {
    const transaction = makeMockTransactionActivity({
      id: 'ltc-tx',
      amount: 100000n,
      fee: 1000n,
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 20 * 60,
      status: 'pending',
      isIncoming: true,
      fromAddress: 'ltc1qsender0000000000000000000000000000000',
      toAddress: 'ltc1qvmw9dmensxtuxu5vw7mxtxqurad2u99m9cqgtp',
      slug: LITECOIN_TOKEN.slug,
    });

    TeactDOM.render(
      <TransactionInfo
        transaction={transaction}
        tokensBySlug={{ [LITECOIN_TOKEN.slug]: LITECOIN_TOKEN }}
        currentAccountId="0-mainnet"
        baseCurrency="USD"
        currencyRates={CURRENCY_RATES}
        theme="light"
      />,
      root,
    );
    await pause(20);

    const textContent = root.textContent || '';
    expect(textContent).toContain('Estimated Time');
    expect(textContent).toContain('~ 20 minutes');
    expect(textContent.indexOf('Estimated Time')).toBeLessThan(textContent.indexOf('Fee'));
  });
});
