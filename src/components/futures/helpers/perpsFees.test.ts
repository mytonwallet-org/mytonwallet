import type { ApiPerpsBalanceWithdrawalQuote } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { formatPerpsUsdc, MISSING_VALUE } from './formatPerps';
import { buildPerpsFeeHint, buildPerpsFeeLines, buildPerpsWithdrawalFee } from './perpsFees';

const lang = ((key: string) => key) as LangFn;

function formatValue(value?: string) {
  return value === undefined ? MISSING_VALUE : `≈ ${value}`;
}

describe('buildPerpsFeeLines', () => {
  it('splits the trading fee and adds the total after the bridge fee', () => {
    const fees = {
      exchange: '0.1', service: '0.2', trading: '0.3', bridge: '1', firstTransfer: '1', total: '2.3',
    };

    expect(buildPerpsFeeLines(lang, fees, formatValue)).toEqual([
      { label: 'PerpsExchangeFee', value: '≈ 0.1' },
      { label: 'PerpsServiceFee', value: '≈ 0.2' },
      { label: 'PerpsBridgeFee', value: '≈ 1' },
      { label: 'PerpsFirstWithdrawalFee', value: '≈ 1' },
      { label: 'PerpsTotalFees', value: '≈ 2.3' },
    ]);
  });

  it('keeps an unknown bridge fee as a dash and leaves out the total', () => {
    expect(buildPerpsFeeLines(lang, { trading: '0.3', total: '0.3' }, formatValue)).toEqual([
      { label: 'Trading Fee', value: '≈ 0.3' },
      { label: 'PerpsBridgeFee', value: MISSING_VALUE },
    ]);
  });

  it('lists no bridge fee for an order paid from the Hyperliquid balance', () => {
    expect(buildPerpsFeeLines(lang, { trading: '0.3', total: '0.3' }, formatValue, { isFromBalance: true })).toEqual([
      { label: 'Trading Fee', value: '≈ 0.3' },
    ]);
  });

  it('leaves out the parts without a known amount when asked', () => {
    expect(buildPerpsFeeLines(lang, { trading: '0.3', total: '0.3' }, formatValue, { shouldSkipUnknown: true }))
      .toEqual([{ label: 'Trading Fee', value: '≈ 0.3' }]);
  });
});

describe('buildPerpsFeeHint', () => {
  const lines = [{ label: 'Trading Fee', value: '≈ 0.3' }, { label: 'Network Fee', value: '≈ 0.1' }];

  it('separates the pending notice, the parts and the estimate notice with a blank line', () => {
    expect(buildPerpsFeeHint(lang, { lines, isPending: true, isEstimated: true })).toBe(
      'PerpsFeesAtExecution\n\nTrading Fee: ≈ 0.3\nNetwork Fee: ≈ 0.1\n\nPerpsFeeEstimateHint',
    );
  });

  it('describes a known fee without parts in general', () => {
    expect(buildPerpsFeeHint(lang, { lines: [] })).toBe('$perps_fees_hint');
  });

  it('tells only that a pending fee without parts becomes known at execution', () => {
    expect(buildPerpsFeeHint(lang, { lines: [], isPending: true })).toBe('PerpsFeesAtExecution');
  });
});

describe('buildPerpsWithdrawalFee', () => {
  const withdrawal = { bridgeFee: '0.2', amount: '9.91' } as ApiPerpsBalanceWithdrawalQuote;

  it('sums the bridge fee and the fee of the first withdrawal', () => {
    const { total, lines } = buildPerpsWithdrawalFee(lang, { ...withdrawal, firstTransferFee: '1' });

    expect(total).toBe(formatPerpsUsdc('1.2'));
    expect(lines.map(({ label }) => label)).toEqual(['PerpsBridgeFee', 'PerpsFirstWithdrawalFee']);
  });

  it('charges only the bridge fee once the first withdrawal is paid', () => {
    const { total, lines } = buildPerpsWithdrawalFee(lang, withdrawal);

    expect(total).toBe(formatPerpsUsdc('0.2'));
    expect(lines).toEqual([{ label: 'PerpsBridgeFee', value: formatPerpsUsdc('0.2') }]);
  });

  it('shows a dash for a fee that is not a number', () => {
    expect(buildPerpsWithdrawalFee(lang, { ...withdrawal, bridgeFee: '' }).total).toBe(MISSING_VALUE);
  });
});
