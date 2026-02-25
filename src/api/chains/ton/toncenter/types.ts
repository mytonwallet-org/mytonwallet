export type AddressBook = Record<string, {
  user_friendly: string;
  domain: string | null;
}>;

export type AccountState = {
  account_state_hash: string;
  address: string;
  balance: string;
  code_boc: string;
  code_hash: string;
  data_boc: string;
  data_hash: string;
  frozen_hash: string;
  last_transaction_hash: string;
  last_transaction_lt: number;
  status: string;
};

export type WalletVersion = 'wallet v1 r1' | 'wallet v1 r2' | 'wallet v1 r3' | 'wallet v2 r1' | 'wallet v2 r2'
  | 'wallet v3 r1' | 'wallet v3 r2' | 'wallet v4 r2' | 'wallet v5 r1';

type CommonWalletState = {
  address: string;
  balance: string;
  last_transaction_hash: string;
  last_transaction_lt: number;
};

type AciveWalletState = CommonWalletState & {
  status: 'active';
  is_wallet: true;
  code_hash: string;
  is_signature_allowed: boolean;
  seqno: number;
  wallet_id: number;
  wallet_type: WalletVersion;
};

type ActiveNotWalletState = CommonWalletState & {
  status: 'active';
  is_wallet: false;
  code_hash: string;
};

type InactiveWalletState = CommonWalletState & {
  status: 'uninit';
  is_wallet: false;
};

export type WalletState = AciveWalletState | ActiveNotWalletState | InactiveWalletState;

// Actions
type BaseAction = {
  /** May be null in early pending actions, otherwise doesn't change. Not unique. */
  trace_id: string | null;
  /** May change during the lifetime of pending actions. Unique within all actions. */
  action_id: string;
  /**
   * Raw addresses that the action belongs to.
   * Always presented in the socket and /api/v3/pendingActions.
   * Presented in /api/v3/actions only when `include_accounts=true` is set in the request.
   */
  accounts?: string[];
  /** May change during the lifetime of pending actions */
  start_lt: string;
  /** May change during the lifetime of pending actions */
  end_lt: string;
  start_utime: number;
  end_utime: number;
  transactions: string[];
  success: boolean;
  trace_end_lt: string;
  trace_end_utime: number;
  trace_mc_seqno_end: number;
  /** Never changes. Not unique. */
  trace_external_hash: string;
  /** Never changes. Not unique. Undefined if the same as `trace_external_hash`. */
  trace_external_hash_norm?: string;
};

export type AnyAction = TonTransferAction
  | CallContractAction
  | ContractDeployAction
  | JettonMintAction
  | JettonTransferAction
  | JettonBurnAction
  | NftMintAction
  | NftTransferAction
  | SwapAction
  | DexDepositLiquidityAction
  | DexWithdrawLiquidityAction
  | StakeDepositAction
  | StakeWithdrawalAction
  | StakeWithdrawalRequestAction
  | AuctionBidAction
  | ChangeDnsAction
  | DeleteDnsAction
  | RenewDnsAction
  | SubscribeAction
  | UnsubscribeAction;

export type DnsAction = ChangeDnsAction | RenewDnsAction | DeleteDnsAction;

export type MetadataMap = Record<string, {
  is_indexed: boolean;
  token_info: AnyTokenMetadata[];
}>;

export type StakingProvider = 'tonstakers' | 'nominators' | (string & {});
export type DexSlug = 'stonfi' | 'stonfi_v2' | 'dedust';
export type MarketplaceSlug = 'fragment' | 'getgems';
export type AnyTokenMetadata = NftCollectionMetadata | NftItemMetadata | JettonMasterMetadata;

export type TonTransferAction = BaseAction & {
  type: 'ton_transfer';
  details: {
    source: string;
    destination: string;
    value: string;
    comment: string | null;
    encrypted: boolean;
  };
};

export type JettonTransferAction = BaseAction & {
  type: 'jetton_transfer';
  details: {
    asset: string;
    sender: string;
    receiver: string;
    sender_jetton_wallet: string;
    receiver_jetton_wallet: string;
    amount: string;
    comment: string | null;
    is_encrypted_comment: boolean;
    query_id: string;
    response_destination: string;
    custom_payload: string | null;
    forward_payload: string | null;
    forward_amount: string;
  };
};

export type NftTransferAction = BaseAction & {
  type: 'nft_transfer';
  details: {
    nft_collection: string | null;
    nft_item: string;
    nft_item_index: string | null;
    new_owner: string;
    old_owner?: string;
    is_purchase: boolean;
    query_id: string;
    response_destination: string | null;
    custom_payload: string | null;
    forward_payload: string;
    forward_amount: string | null;
    price: string | null;
    marketplace: MarketplaceSlug | null;
    payout_amount: string | null;
  };
};

export type CallContractAction = BaseAction & {
  type: 'call_contract';
  details: {
    opcode: string;
    source: string;
    destination: string;
    value: string;
  };
};

export type ContractDeployAction = BaseAction & {
  type: 'contract_deploy';
  details: {
    opcode?: string;
    source?: string; // Missing, if it’s wallet deployment
    destination: string;
    value: string;
  };
};

export type StakeDepositAction = BaseAction & {
  type: 'stake_deposit';
  details: {
    provider: StakingProvider;
    stake_holder: string;
    pool: string;
    amount: string;
  };
};

export type StakeWithdrawalAction = BaseAction & {
  type: 'stake_withdrawal';
  details: {
    provider: StakingProvider;
    stake_holder: string;
    pool: string | null;
    amount: string;
    payout_nft: string | null;
  };
};

export type StakeWithdrawalRequestAction = BaseAction & {
  type: 'stake_withdrawal_request';
  details: {
    provider: StakingProvider;
    stake_holder: string;
    pool: string;
    payout_nft: string | null;
  };
};

export type SwapAction = BaseAction & {
  type: 'jetton_swap';
  details: {
    dex: DexSlug;
    sender: string;
    asset_in: string | null;
    asset_out: string | null;
    dex_incoming_transfer: {
      asset: string | null;
      source: string;
      destination: string;
      source_jetton_wallet: string | null;
      destination_jetton_wallet: string | null;
      amount: string;
    };
    dex_outgoing_transfer: {
      asset: string | null;
      source: string;
      destination: string;
      source_jetton_wallet: string | null;
      destination_jetton_wallet: string | null;
      amount: string;
    };
    peer_swaps: unknown[];
  };
};

export type AuctionBidAction = BaseAction & {
  type: 'auction_bid';
  details: {
    amount: string;
    bidder: string;
    auction: string;
    nft_item: string;
    nft_collection: string | null;
    nft_item_index: string | null;
  };
};

export type ChangeDnsAction = BaseAction & {
  type: 'change_dns';
  details: {
    key: string;
    value: {
      sum_type: 'DNSSmcAddress' | 'DNSAdnlAddress' | 'DNSNextResolver' | 'DNSStorageAddress';
      dns_smc_address: string | null;
      flags: number | null;
    };
    source: string;
    asset: string;
  };
};

/*
  This is the only action combining two outgoing transactions from the wallet.
  However, a deposit can consist of separate actions from the wallet in case of Ledger:
  - STON.fi v2: One without `lp_tokens_minted`, both with `amount_2` equal `null` (one action per deposited token);
  - DeDust: Both actions contain the same deposited amounts, but one of the actions has no `lp_tokens_minted` and no
    `pool`, and the real fee is spread across both actions;
*/
export type DexDepositLiquidityAction = BaseAction & {
  type: 'dex_deposit_liquidity';
  details: {
    dex: DexSlug;
    amount_1: string | null;
    amount_2: string | null;
    asset_1: string | null;
    asset_2: string | null;
    user_jetton_wallet_1: string | null;
    user_jetton_wallet_2: string | null;
    source: string;
    pool: string | null;
    destination_liquidity: string;
    lp_tokens_minted: string | null;
  };
};

export type DexWithdrawLiquidityAction = BaseAction & {
  type: 'dex_withdraw_liquidity';
  details: {
    dex: DexSlug;
    amount_1: string;
    amount_2: string;
    asset_1: string | null;
    asset_2: string | null;
    user_jetton_wallet_1: string | null;
    user_jetton_wallet_2: string | null;
    lp_tokens_burnt: string;
    is_refund: boolean | null;
    source: string;
    pool: string;
    destination_liquidity: string;
  };
};

export type DeleteDnsAction = BaseAction & {
  type: 'delete_dns';
  details: {
    hash: string;
    source: string;
    asset: string;
  };
};

export type RenewDnsAction = BaseAction & {
  type: 'renew_dns';
  details: {
    source: string;
    asset: string;
  };
};

export type JettonBurnAction = BaseAction & {
  type: 'jetton_burn';
  details: {
    owner: string;
    owner_jetton_wallet: string;
    asset: string;
    amount: string;
  };
};

export type JettonMintAction = BaseAction & {
  type: 'jetton_mint';
  details: {
    asset: string;
    receiver: string;
    receiver_jetton_wallet: string;
    amount: string;
    ton_amount: string;
  };
};

export type NftMintAction = BaseAction & {
  type: 'nft_mint';
  details: {
    owner: string;
    nft_item: string;
    nft_collection: string | null;
    nft_item_index: string;
  };
};

export type SubscribeAction = BaseAction & {
  type: 'subscribe';
  details: {
    subscriber: string;
    beneficiary: string;
    subscription: string;
    amount: string;
  };
};

export type UnsubscribeAction = BaseAction & {
  type: 'unsubscribe';
  details: {
    subscriber: string;
    subscription: string;
  };
};

type BaseExtra = {
  uri?: string;
  _image_big?: string;
  _image_medium?: string;
  _image_small?: string;
};

export type NftCollectionMetadata = {
  type: 'nft_collections';
  name?: string;
  description?: string;
  image?: string;
  extra?: BaseExtra & {
    uri?: string;
    render_type?: 'hidden' | (string & {});
    marketplace?: string;
    cover_image?: string;
  };
};

export type NftItemMetadata = {
  type: 'nft_items';
  name?: string;
  description?: string;
  image?: string;
  extra?: BaseExtra & {
    attributes?: {
      trait_type: string;
      value: string;
    }[];
    render_type?: 'hidden' | (string & {});
    marketplace?: string;
    domain?: string;
    lottie?: string;
  };
};

export type JettonMasterMetadata = {
  type: 'jetton_masters';
  name?: string;
  symbol?: string;
  description?: string;
  image?: string;
  extra?: BaseExtra & {
    decimals?: string;
  };
};

export type Trace = {
  trace_id: string;
  external_hash: string;
  mc_seqno_start: string;
  mc_seqno_end: string;
  start_lt: string;
  start_utime: number;
  end_lt: string;
  end_utime: number;
  trace_info: {
    trace_state: string;
    messages: number;
    transactions: number;
    pending_messages: number;
    classification_state: string;
  };
  is_incomplete: boolean;
  actions: AnyAction[];
  trace: TraceDetail;
  transactions_order: string[];
  transactions: Record<string, Transaction>;
};

export type TraceDetail = {
  tx_hash: string;
  in_msg_hash: string;
  children: TraceDetail[];
};

export type Transaction = {
  account: string;
  hash: string;
  lt: string;
  now: number;
  mc_block_seqno: number;
  trace_id: string;
  prev_trans_hash: string;
  prev_trans_lt: string;
  orig_status: string;
  end_status: string;
  total_fees: string;
  total_fees_extra_currencies: Record<string, string>;
  description: {
    type: string;
    aborted: boolean;
    destroyed: boolean;
    credit_first: boolean;
    storage_ph: {
      storage_fees_collected: string;
      status_change: string;
    };
    compute_ph: {
      skipped: boolean;
      success: boolean;
      msg_state_used: boolean;
      account_activated: boolean;
      gas_fees: string;
      gas_used: string;
      gas_limit: string;
      gas_credit: string;
      mode: number;
      exit_code: number;
      vm_steps: number;
      vm_init_state_hash: string;
      vm_final_state_hash: string;
    };
    action: {
      success: boolean;
      valid: boolean;
      no_funds: boolean;
      status_change: string;
      total_fwd_fees: string;
      total_action_fees: string;
      result_code: number;
      tot_actions: number;
      spec_actions: number;
      skipped_actions: number;
      msgs_created: number;
      action_list_hash: string;
      tot_msg_size: {
        cells: string;
        bits: string;
      };
    };
  };
  block_ref: {
    workchain: number;
    shard: string;
    seqno: number;
  };
  in_msg: TransactionMessage;
  // eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
  init_state: null | unknown;
  out_msgs: TransactionMessage[];
  account_state_before: TransactionAccountState;
  account_state_after: TransactionAccountState;
  emulated: boolean;
};

export type TransactionMessage = {
  hash: string;
  /** Undefined if the same as `hash` */
  hash_norm?: string;
  source: string | null;
  destination: string | null;
  value: string | null;
  value_extra_currencies: Record<string, string> | null;
  fwd_fee: string | null;
  ihr_fee: string | null;
  created_lt: string | null;
  created_at: number | null;
  opcode: string | null;
  ihr_disabled: boolean | null;
  bounce: boolean | null;
  bounced: boolean | null;
  import_fee: string | null;
  message_content: {
    hash: string;
    body: string;
  };
};

type TransactionAccountState = {
  hash: string;
  balance: string;
  extra_currencies: Record<string, string>;
  account_status: string;
  frozen_hash: string | null;
  data_hash: string;
  code_hash: string;
};

type BaseSocketMessage = {
  id?: string;
};

export type SocketFinality = 'pending' | 'confirmed' | 'signed' | 'finalized';

export type SocketSubscriptionEvent = 'actions' | 'transactions' | 'account_state_change' | 'jettons_change';

export type SubscribeSocketMessage = BaseSocketMessage & {
  operation: 'subscribe';
  addresses: string[];
  types: SocketSubscriptionEvent[];
  min_finality?: SocketFinality;
  include_address_book?: boolean;
  include_metadata?: boolean;
  action_types?: string[];
  /** @default ['latest'] */
  supported_action_types?: ('v1' | 'v2' | 'latest')[];
};

export type UnsubscribeSocketMessage = BaseSocketMessage & {
  operation: 'unsubscribe';
  addresses: string[];
};

export type PingSocketMessage = BaseSocketMessage & {
  operation: 'ping';
};

export type ClientSocketMessage =
  | SubscribeSocketMessage
  | UnsubscribeSocketMessage
  | PingSocketMessage;

export type StatusSocketMessage = BaseSocketMessage & {
  status: 'subscribed' | 'unsubscribed' | 'pong';
};

export type ActionsSocketMessage = BaseSocketMessage & {
  type: 'actions';
  finality: SocketFinality;
  trace_external_hash_norm: string;
  actions: AnyAction[];
  address_book: AddressBook;
  metadata: MetadataMap;
};

export type TransactionsSocketMessage = BaseSocketMessage & {
  type: 'transactions';
  finality: SocketFinality;
  trace_external_hash_norm: string;
  transactions: TransactionMessage[];
  address_book: AddressBook;
  metadata: MetadataMap;
};

export type InvalidationSocketMessage = BaseSocketMessage & {
  type: 'trace_invalidated';
  trace_external_hash_norm: string;
};

export type AccountStateChangeSocketMessage = BaseSocketMessage & {
  type: 'account_state_change';
  finality: Exclude<SocketFinality, 'pending'>;
  /** Raw address */
  account: string;
  state: {
    /** Base64 */
    hash: string;
    /** Stringified integer */
    balance: string;
    account_status: 'active' | 'uninit';
    /** Base64 */
    data_hash: string;
    /** Base64 */
    code_hash: string;
  };
};

export type JettonChangeSocketMessage = BaseSocketMessage & {
  type: 'jettons_change';
  finality: Exclude<SocketFinality, 'pending'>;
  jetton: {
    /** The token wallet raw address */
    address: string;
    /** Stringified integer */
    balance: string;
    /** The wallet raw address */
    owner: string;
    /** The token raw address */
    jetton: string;
    /** Stringified integer */
    last_transaction_lt: string;
  };
  address_book: AddressBook;
  metadata: MetadataMap;
};

/** Server messages from the streaming API */
export type ServerSocketMessage =
  | StatusSocketMessage
  | ActionsSocketMessage
  | TransactionsSocketMessage
  | InvalidationSocketMessage
  | AccountStateChangeSocketMessage
  | JettonChangeSocketMessage;
