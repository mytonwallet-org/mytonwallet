import type { UtxoListItem } from './types';

import { getSpendableBalance, getSpendableUtxos, isSpendableUtxo } from './utxos';

function utxo(overrides: Partial<UtxoListItem> & Pick<UtxoListItem, 'txid' | 'value'>): UtxoListItem {
  return {
    vout: 0,
    confirmations: 3,
    ...overrides,
  };
}

describe('UTXO spendable set', () => {
  it('counts only confirmed outputs', () => {
    const confirmed = utxo({ txid: 'aa'.repeat(32), value: '1000' });
    const unconfirmed = utxo({
      txid: 'bb'.repeat(32),
      vout: 1,
      value: '400',
      height: 0,
      confirmations: 0,
    });
    const spendable = getSpendableUtxos([confirmed, unconfirmed]);

    expect(spendable).toEqual([confirmed]);
    expect(getSpendableBalance(spendable)).toBe(1000n);
  });

  it('excludes immature coinbase', () => {
    const confirmed = utxo({ txid: 'ee'.repeat(32), value: '400' });
    const immatureCoinbase = utxo({
      txid: 'ff'.repeat(32),
      value: '5000',
      confirmations: 20,
      coinbase: true,
    });

    expect(isSpendableUtxo(confirmed)).toBe(true);
    expect(isSpendableUtxo(immatureCoinbase)).toBe(false);
    expect(getSpendableBalance(getSpendableUtxos([confirmed, immatureCoinbase]))).toBe(400n);
  });
});
