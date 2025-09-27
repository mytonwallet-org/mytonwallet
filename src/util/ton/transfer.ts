import type {
  ApiAccountWithChain,
  ApiNftTransferPayload,
  ApiParsedPayload,
  ApiTokensTransferNonStandardPayload,
  ApiTokensTransferPayload,
} from '../../api/types';

import { DEFAULT_MAX_MESSAGES, LEDGER_MAX_MESSAGES, W5_MAX_MESSAGES } from '../../api/chains/ton/constants';

export function isNftTransferPayload(payload: ApiParsedPayload | undefined): payload is ApiNftTransferPayload {
  return payload?.type === 'nft:transfer';
}

export function isTokenTransferPayload(
  payload: ApiParsedPayload | undefined,
): payload is ApiTokensTransferPayload | ApiTokensTransferNonStandardPayload {
  return payload?.type === 'tokens:transfer' || payload?.type === 'tokens:transfer-non-standard';
}

/** How many messages can be sent in a single transaction */
export function getMaxMessagesInTransaction(account: ApiAccountWithChain<'ton'>) {
  const { type, byChain: { ton: { version } } } = account;

  if (type === 'ledger') {
    return LEDGER_MAX_MESSAGES;
  } else if (version === 'W5') {
    return W5_MAX_MESSAGES;
  } else {
    return DEFAULT_MAX_MESSAGES;
  }
}
