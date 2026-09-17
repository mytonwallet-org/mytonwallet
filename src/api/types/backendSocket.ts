import type { UtxoTransaction } from '../chains/utxo/types';
import type { ApiChain, ApiTransaction, UTXOChain } from './misc';

export type ApiSocketEventType = 'activity';

type ApiSubscriptionAddress = {
  chain: ApiChain;
  address: string;
  events: ApiSocketEventType[];
};

type ApiBaseClientSocketMessage = {
  /** An arbitrary unique (within the socket connection) id to link the response with the request */
  id: number;
};

type ApiSubscribeSocketMessage = ApiBaseClientSocketMessage & {
  type: 'subscribe';
  addresses: ApiSubscriptionAddress[];
};

type ApiOkSocketMessage = {
  type: 'ok';
  /** The id from the request */
  id: number;
};

type ApiErrorSocketMessage = {
  type: 'error';
  /** The id from the request */
  id?: number;
  error: string;
};

export type ApiNewActivitySocketMessage = {
  type: 'newActivity';
  blockId: number;
  chain: ApiChain;
  addresses: string[];
};

type ApiUtxoActivityUpdateSocketMessageBase = {
  type: 'utxoActivityUpdate';
  chain: UTXOChain;
  address: string;
  txId: string;
  status: Extract<ApiTransaction['status'], 'pending' | 'completed'>;
  /** Backend-owned confirmation target for this update. */
  maxConfirmations: number;
  /** Backend-owned approximate seconds until UTXO finality when available. */
  etaSeconds?: number;
  /** Raw Blockbook transaction JSON. Parse relative to the subscribed wallet address. */
  rawTransaction: UtxoTransaction;
};

export type ApiUtxoUnconfirmedActivityUpdateSocketMessage = ApiUtxoActivityUpdateSocketMessageBase & {
  confirmations: 0;
  status: 'pending';
  blockHeight?: undefined;
  blockHash?: undefined;
};

export type ApiUtxoConfirmedActivityUpdateSocketMessage = ApiUtxoActivityUpdateSocketMessageBase & {
  /** Positive confirmation count. Confirmed UTXO updates must include block identity. */
  confirmations: number;
  blockHeight: number;
  blockHash: string;
};

export type ApiUtxoActivityUpdateSocketMessage =
  | ApiUtxoUnconfirmedActivityUpdateSocketMessage
  | ApiUtxoConfirmedActivityUpdateSocketMessage;

export type ApiSubscribedSocketMessage = {
  type: 'subscribed';
  /** The id from the request */
  id: number;
};

export type ApiClientSocketMessage = ApiSubscribeSocketMessage;
export type ApiServerSocketMessage =
  | ApiOkSocketMessage
  | ApiErrorSocketMessage
  | ApiSubscribedSocketMessage
  | ApiNewActivitySocketMessage
  | ApiUtxoActivityUpdateSocketMessage;
