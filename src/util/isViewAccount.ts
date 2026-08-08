import type { Account, AccountType } from '../global/types';

import { DEBUG_VIEW_ACCOUNTS, IS_EXPLORER } from '../config';

export default function isViewAccount(accountType?: AccountType) {
  return !DEBUG_VIEW_ACCOUNTS && (accountType === 'view' || IS_EXPLORER);
}

export function getIsViewAccountDisabled(account: Account) {
  return isViewAccount(account.type);
}
