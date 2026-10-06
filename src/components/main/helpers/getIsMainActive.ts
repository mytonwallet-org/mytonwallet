import type { GlobalState } from '../../../global/types';

import { selectCurrentAccountId } from '../../../global/selectors';

// After an account switch the outgoing Main keeps showing the previous account while the new one fades in
// over it. With the landscape Agent open, `App` keeps the same Main and passes it the new account instead.
export function getIsMainActive(global: GlobalState, { accountId }: { accountId?: string }) {
  return selectCurrentAccountId(global) === accountId;
}
