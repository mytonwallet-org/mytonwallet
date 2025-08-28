import type { ConnectEventError, ConnectEventSuccess } from '@tonconnect/protocol';

export interface TransactionPayload {
  valid_until?: number;
  network?: CHAIN;
  from?: string; // https://github.com/ton-blockchain/ton-connect/blob/main/wallet-guidelines.md#multi-accounts
  messages: TransactionPayloadMessage[];
}

export interface TransactionPayloadMessage {
  address: string;
  amount: string;
  payload?: string;
  stateInit?: string;
}

// This and the other enums can be imported from @tonconnect/protocol. We copy the enums instead of importing because
// importing that module increases the compiled code size significantly.

export enum CONNECT_EVENT_ERROR_CODES {
  UNKNOWN_ERROR = 0,
  BAD_REQUEST_ERROR = 1,
  MANIFEST_NOT_FOUND_ERROR = 2,
  MANIFEST_CONTENT_ERROR = 3,
  UNKNOWN_APP_ERROR = 100,
  USER_REJECTS_ERROR = 300,
  METHOD_NOT_SUPPORTED = 400,
}

export enum SEND_TRANSACTION_ERROR_CODES {
  UNKNOWN_ERROR = 0,
  BAD_REQUEST_ERROR = 1,
  UNKNOWN_APP_ERROR = 100,
  USER_REJECTS_ERROR = 300,
  METHOD_NOT_SUPPORTED = 400,
}

export type AllErrorCodes = CONNECT_EVENT_ERROR_CODES | SEND_TRANSACTION_ERROR_CODES;
export type ConnectEvent = ConnectEventSuccess | ConnectEventError;

export interface ApiTonConnectProof {
  timestamp: number;
  domain: string;
  payload: string;
}

export enum CHAIN {
  MAINNET = '-239',
  TESTNET = '-3',
}

export interface ApiDappRequestConfirmation {
  accountId: string;
  /** Base64. Shall miss when no proof is required. */
  proofSignature?: string;
}
