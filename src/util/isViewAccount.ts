import type { AccountType } from '../global/types';

import { DEBUG_VIEW_ACCOUNTS, IS_EXPLORER } from '../config';

export default function isViewAccount(accountType?: AccountType) {
  return !DEBUG_VIEW_ACCOUNTS && (accountType === 'view' || IS_EXPLORER);
}
