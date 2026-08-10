import type { Account, AccountType } from '../global/types';

import { DEBUG_VIEW_ACCOUNTS, IS_EXPLORER } from '../config';

export default function isViewAccount(accountType?: AccountType) {
  return !DEBUG_VIEW_ACCOUNTS && (accountType === 'view' || IS_EXPLORER);
}

export function getIsViewAccountDisabled(account: Account) {
  // A wallet whose stored secret the Enclave migration could not read has nothing to sign with, so the signing
  // pickers treat it as watch-only instead of letting a person fill in a form that can only end on a refusal.
  return isViewAccount(account.type) || !!account.isRecoveryRequired;
}
