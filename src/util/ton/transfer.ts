import type {
  ApiAccountWithChain,
  ApiDappTransfer,
  ApiNftTransferPayload,
  ApiParsedPayload,
  ApiTokensTransferNonStandardPayload,
  ApiTokensTransferPayload,
} from '../../api/types';

import {
  DEFAULT_MAX_MESSAGES,
  LEDGER_MAX_MESSAGES,
  TELEGRAM_WALLET_MAX_MESSAGES,
  W5_MAX_MESSAGES,
} from '../../api/chains/ton/constants';

export function isNftTransferPayload(payload: ApiParsedPayload | undefined): payload is ApiNftTransferPayload {
  return payload?.type === 'nft:transfer';
}

export function isTokenTransferPayload(
  payload: ApiParsedPayload | undefined,
): payload is ApiTokensTransferPayload | ApiTokensTransferNonStandardPayload {
  return payload?.type === 'tokens:transfer' || payload?.type === 'tokens:transfer-non-standard';
}

/** Returns the recipient declared in the payload when it differs from the address the message is sent to */
export function getPayloadRecipientAddress({ toAddress, payload }: Pick<ApiDappTransfer, 'toAddress' | 'payload'>) {
  let recipientAddress: string | undefined;
  if (isNftTransferPayload(payload)) {
    recipientAddress = payload.newOwner;
  } else if (isTokenTransferPayload(payload)) {
    recipientAddress = payload.destination;
  }
  return recipientAddress !== toAddress ? recipientAddress : undefined;
}

/** How many messages can be sent in a single transaction */
export function getMaxMessagesInTransaction(account: ApiAccountWithChain<'ton'>) {
  const { type, byChain: { ton: { version } } } = account;

  if (type === 'ledger') {
    return LEDGER_MAX_MESSAGES;
  } else if (version === 'W5') {
    return W5_MAX_MESSAGES;
  } else if (version === 'telegram') {
    return TELEGRAM_WALLET_MAX_MESSAGES;
  } else {
    return DEFAULT_MAX_MESSAGES;
  }
}
