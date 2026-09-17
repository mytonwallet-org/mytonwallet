import type { ApiActivity, UTXOChain } from '../../types';

export type UtxoAddressInfo = {
  page?: number;
  totalPages?: number;
  itemsOnPage?: number;
  address: string;
  balance: string;
  unconfirmedBalance?: string;
  txs: number;
  txids: string[];
  transactions?: UtxoTransaction[];
};

export type UtxoTransactionVin = {
  txid?: string;
  vout?: number;
  addresses?: string[];
  isAddress?: boolean;
  value?: string;
  n?: number;
};

export type UtxoTransactionVout = {
  value: string;
  n: number;
  addresses?: string[];
  isAddress?: boolean;
  hex?: string;
};

export type UtxoTransaction = {
  txid: string;
  version?: number;
  vin: UtxoTransactionVin[];
  vout: UtxoTransactionVout[];
  blockHash?: string;
  blockHeight?: number;
  blockTime?: number;
  confirmations?: number;
  value?: string;
  valueIn?: string;
  fees?: string;
};

export type UtxoListItem = {
  txid: string;
  vout: number;
  value: string;
  height?: number;
  confirmations?: number;
  coinbase?: boolean;
  address?: string;
};

export type UtxoListResponse = UtxoListItem[];

export type UtxoSendTxResponse = {
  result?: string;
};

export type UtxoSocketClientMessage = {
  id: string;
  method: string;
  params?: Record<string, unknown>;
};

export type UtxoSocketSubscribeResult = {
  id: string;
  data: {
    subscribed: boolean;
  };
};

export type UtxoSocketAddressEvent = {
  id: string;
  data: {
    address: string;
    tx: UtxoTransaction;
  };
};

export type UtxoSocketServerMessage = UtxoSocketSubscribeResult | UtxoSocketAddressEvent;

export type UtxoWatchedWallet = {
  address: string;
  chain: UTXOChain;
};

export type UtxoActivitiesUpdate = {
  address: string;
  activities: ApiActivity[];
};
