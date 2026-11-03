import type { ApiChain } from '../../types';

import { createCallbackManager } from '../../../util/callbacks';

/** Requests an authoritative refresh through the existing balance stream, without fabricating a balance. */
export const balanceRefreshRequests = createCallbackManager<(accountId: string, chain: ApiChain) => void>();
