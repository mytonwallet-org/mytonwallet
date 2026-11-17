import type { ApiPerpsMarketAsset, ApiPerpsQuote } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { WHOLE_PART_DELIMITER } from '../../../config';
import {
  formatPerpsFeeEstimate,
  formatPerpsFundingPercent,
  formatPerpsMoneyEstimate,
  formatPerpsNetworkFee,
  formatPerpsQuantity,
  formatPerpsSignedMoney,
  getPerpsErrorText,
  getPerpsValueTone,
  MISSING_VALUE,
} from './formatPerps';

const lang = ((key: string, vars?: Record<string, string>) => (
  vars ? `${key} ${Object.values(vars).join(' ')}` : key
)) as LangFn;

function buildQuote(quote: Partial<ApiPerpsQuote>) {
  return { paymentAmount: '20', ...quote } as ApiPerpsQuote;
}

describe('formatPerpsNetworkFee', () => {
  it('shows the gas of a deposit in dollars, or in ETH while its price is unknown', () => {
    expect(formatPerpsNetworkFee(buildQuote({ estimatedNetworkFeeUsd: '0.25', estimatedNetworkFeeEth: '0.0001' })))
      .toContain('0.25');
    expect(formatPerpsNetworkFee(buildQuote({ estimatedNetworkFeeEth: '0.0001' }))).toContain('ETH');
  });

  it('shows the gas in USDC when the wallet lacks ETH for it', () => {
    expect(formatPerpsNetworkFee(buildQuote({ estimatedNetworkFeeUsdc: '0.024' }))).toBe('≈ 0.024 USDC');
  });

  it('shows a dash for a deposit the SDK could not estimate', () => {
    expect(formatPerpsNetworkFee(buildQuote({}))).toBe(MISSING_VALUE);
  });

  it.each([
    ['an order paid from the Hyperliquid balance', { funding: 'balance' as const }],
    ['a reduce, which returns the margin', { receiveStatus: 'pending' as const }],
    ['a change without a deposit', { paymentAmount: '0' }],
  ])('leaves out %s', (_, quote) => {
    expect(formatPerpsNetworkFee(buildQuote(quote))).toBeUndefined();
  });
});

describe('estimates', () => {
  it('shows a price below a cent as a price, unlike a fee', () => {
    expect(formatPerpsMoneyEstimate('0.004')).toBe('≈ $0.004');
    expect(formatPerpsFeeEstimate('0.004')).toBe('<$0.01');
  });
});

describe('formatPerpsSignedMoney and getPerpsValueTone', () => {
  it('shows zero without a sign and a colour, as on iOS', () => {
    expect(formatPerpsSignedMoney('0')).toBe('$0');
    expect(getPerpsValueTone('0')).toBeUndefined();
    expect(getPerpsValueTone('-1')).toBe('negative');
  });
});

describe('formatPerpsQuantity', () => {
  it('groups the digits of a coin amount', () => {
    expect(formatPerpsQuantity('BTC', '-1250.005')).toBe(`1${WHOLE_PART_DELIMITER}250.005 BTC`);
  });
});

describe('formatPerpsFundingPercent', () => {
  it('rounds the rate to six decimals', () => {
    const asset = { context: { fundingPercent: '0.00123456789' } } as ApiPerpsMarketAsset;

    expect(formatPerpsFundingPercent(asset)).toBe('0.001235%');
  });
});

describe('getPerpsErrorText', () => {
  it.each([
    ['rounds a minimum up to a cent that passes', '10.001', false, '10.01'],
    ['keeps a minimum in whole cents', '10', false, '10'],
    ['adds a cent to an exclusive minimum rounded down', '5.009', true, '5.01'],
    ['adds a cent to an exclusive minimum in whole cents', '5', true, '5.01'],
  ])('%s, as on iOS', (_, minimumAmount, isMinimumExclusive, shown) => {
    expect(getPerpsErrorText(lang, 'PerpsAmountTooSmall', { minimumAmount, isMinimumExclusive }))
      .toBe(`$perps_minimum_amount ${shown}`);
  });

  it('tells by how much a reduce must exceed the bridge fee', () => {
    expect(getPerpsErrorText(lang, 'PerpsAmountTooSmall', { minimumReduction: '1.2345678' }))
      .toBe('$perps_minimum_reduction 1.234568');
  });

  it('tells the balance an order needs and the balance there is', () => {
    expect(getPerpsErrorText(lang, 'PerpsInsufficientBalance', { requiredBalance: '3.01', availableBalance: '0.5' }))
      .toBe('$perps_required_balance 3.01 0.5');
    expect(getPerpsErrorText(lang, 'PerpsInsufficientBalance', { availableBalance: '0.5' }))
      .toBe('$perps_available_balance 0.5');
  });

  it('shows the text of the code without the amounts it needs', () => {
    expect(getPerpsErrorText(lang, 'PerpsAmountTooSmall')).toBe('PerpsAmountTooSmall');
    expect(getPerpsErrorText(lang, 'PerpsInsufficientBalance', { requiredBalance: '3.01' }))
      .toBe('PerpsInsufficientBalance');
    expect(getPerpsErrorText(lang, 'PerpsQuoteExpired', { minimumAmount: '10' })).toBe('PerpsQuoteExpired');
  });
});
