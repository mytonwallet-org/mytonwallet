import type { Account } from '../../../../../global/types';

import { getVisibleWallets } from './visibleWallets';

const CURRENT_ID = 'current';

function buildAccounts(otherCount: number) {
  const others = Array.from({ length: otherCount }, (_, index) => `other-${index}`);

  return [CURRENT_ID, ...others].map((id): [string, Account] => [id, {} as Account]);
}

function getShownIds(otherCount: number) {
  return getVisibleWallets(buildAccounts(otherCount), CURRENT_ID, true).visibleWallets.map(([id]) => id);
}

describe('getVisibleWallets', () => {
  it('leaves only the add button when the current wallet is the only one', () => {
    expect(getVisibleWallets(buildAccounts(0), CURRENT_ID, true)).toEqual({
      visibleWallets: [],
      hasExcessWallets: false,
    });
  });

  it('shows all six other wallets without the show-all button', () => {
    const { hasExcessWallets } = getVisibleWallets(buildAccounts(6), CURRENT_ID, true);

    expect(getShownIds(6)).toHaveLength(6);
    expect(getShownIds(6)).not.toContain(CURRENT_ID);
    expect(hasExcessWallets).toBe(false);
  });

  it('collapses seven other wallets to five and the show-all button', () => {
    const { hasExcessWallets } = getVisibleWallets(buildAccounts(7), CURRENT_ID, true);

    expect(getShownIds(7)).toHaveLength(5);
    expect(hasExcessWallets).toBe(true);
  });

  it('keeps the current wallet in the landscape list', () => {
    const { visibleWallets, hasExcessWallets } = getVisibleWallets(buildAccounts(16), CURRENT_ID, false);

    expect(visibleWallets[0][0]).toBe(CURRENT_ID);
    expect(visibleWallets).toHaveLength(16);
    expect(hasExcessWallets).toBe(true);
  });
});
