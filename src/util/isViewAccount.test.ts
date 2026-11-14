import type { Account } from '../global/types';

import { getIsViewAccountDisabled } from './isViewAccount';

jest.mock('../config', () => ({ ...jest.requireActual('../config'), DEBUG_VIEW_ACCOUNTS: false, IS_EXPLORER: false }));

it('disables a card whose account was removed before its unmount during logout', () => {
  expect(getIsViewAccountDisabled(undefined)).toBe(true);
});
it('retains view-only and recovery restrictions for existing accounts', () => {
  expect(getIsViewAccountDisabled({ type: 'view' } as Account)).toBe(true);
  expect(getIsViewAccountDisabled({ type: 'mnemonic', isRecoveryRequired: true } as Account)).toBe(true);
  expect(getIsViewAccountDisabled({ type: 'mnemonic' } as Account)).toBe(false);
});
