import type { BaseApiSwapHistoryItem, BaseApiTransaction, EVMChain, EvmNftInterface } from '../../types';

export type ZerionFungibleInfo = {
  id: string;
  name: string;
  symbol: string;
  icon: { url: string } | null;
  flags: { verified: boolean };
  implementations: {
    chain_id: string;
    address: string | null;
    decimals: number;
  }[];
};

type ZerionNftInfo = {
  content?: {
    detail: {
      url: string;
    };
    preview: {
      url: string;
    };
  };
  contract_address: string;
  flags: {
    is_spam: boolean;
  };
  interface: EvmNftInterface;
  name: string;
  token_id: string;
};

type ZerionTokenAmount = {
  quantity: {
    int: string;
    decimals: number;
    float: number;
    numeric: string;
  };
  price: number | null;
  value: number | null;
};

type ZerionAssetTransferInfo = {
  direction: 'in' | 'out' | 'self';
  sender: string;
  recipient: string;
  act_id: string;
};

export type ZerionTokenTransfer = ZerionTokenAmount & ZerionAssetTransferInfo & {
  fungible_info: ZerionFungibleInfo;
};

export type ZerionNftTransfer = ZerionTokenAmount & ZerionAssetTransferInfo & {
  nft_info: ZerionNftInfo;
};

export type ZerionTransaction = {
  type: 'transactions';
  id: string;
  attributes: {
    address: string;
    operation_type: 'trade' | 'receive' | 'send' | 'execute' | 'approve';
    hash: string;
    mined_at_block: number;
    mined_at: string;
    sent_from: string;
    sent_to: string;
    status: 'confirmed' | 'failed' | 'pending';
    nonce: number;
    fee: ZerionTokenAmount;
    transfers: (ZerionTokenTransfer | ZerionNftTransfer)[];
    approvals: (Omit<ZerionTokenAmount, 'price' | 'value'> & {
      sender: string;
      act_id: string;
    })[];
    application_metadata?: {
      name?: string;
      icon?: { url: string };
      contract_address: string;
      method?: { id: string; name: string };
    };
    flags: { is_trash: boolean };
    acts: {
      id: string;
      type: 'trade' | 'receive' | 'send' | 'execute' | 'approve';
      application_metadata?: ZerionTransaction['attributes']['application_metadata'];
    }[];
    paymaster?: string;
  };
  relationships: {
    chain: {
      links: {
        related: string;
      };
      data: {
        type: 'chains';
        id: string;
      };
    };
    dapp?: {
      data: {
        type: 'dapps';
        id: string;
      };
    };
  };
};

export type ZerionTransactionsResponse = {
  links: {
    self: string;
    next?: string;
  };
  data: ZerionTransaction[];
};

export type ZerionPosition = {
  type: 'positions';
  id: string;
  attributes: {
    parent: string | null;
    protocol: string | null;
    name: string;
    position_type: 'wallet' | 'deposit' | 'loan' | 'reward' | 'staked';
    quantity: {
      int: string;
      decimals: number;
      float: number;
      numeric: string;
    };
    value: number | null;
    price: number | null;
    changes: {
      absolute_1d: number | null;
      percent_1d: number | null;
    } | null;
    fungible_info: Omit<ZerionFungibleInfo, 'id'>;
    flags: {
      displayable: boolean;
      is_trash: boolean;
    };
    updated_at: string;
    updated_at_block: number;
  };
  relationships: {
    chain: {
      links: {
        related: string;
      };
      data: {
        type: 'chains';
        id: string;
      };
    };
    fungible: {
      links: {
        related: string;
      };
      data: {
        type: 'fungibles';
        id: string;
      };
    };
  };
};

export type ZerionPositionsResponse = {
  links: {
    self: string;
  };
  data: ZerionPosition[];
};

export type EvmWatchedWallet = {
  address: string;
  chain: EVMChain;
};

export type EvmSubscriptionType =
  | 'native'
  | 'erc20_in'
  | 'erc20_out'
  | 'erc721_in'
  | 'erc721_out'
  | 'erc1155_in'
  | 'erc1155_out';

export type EvmNftTransferEvent = {
  contractAddress: string;
  from: string;
  to: string;
  tokenType: 'erc721' | 'erc1155';
  /** `undefined` for ERC-1155 TransferBatch — a full poll is required in that case */
  tokenId?: string;
};

export type EthSubscribeRequest = {
  jsonrpc: '2.0';
  id: string;
  method: 'eth_subscribe';
  params:
    | [
      'alchemy_minedTransactions',
      {
        addresses: {
          from?: string;
          to?: string;
        }[];
        includeRemoved: boolean;
        hashesOnly: boolean;
      },
    ]
    | [
      'logs',
      {
        topics: (string | string[] | null | undefined)[];
      },
    ];
};

export type EthUnsubscribeRequest = {
  jsonrpc: '2.0';
  id: string;
  method: 'eth_unsubscribe';
  params: [string];
};

export type AlchemySocketClientMessage = EthSubscribeRequest | EthUnsubscribeRequest;

export type EthSubscribeResultMessage = {
  jsonrpc: '2.0';
  id: string;
  result: string;
};

export type EthUnsubscribeResultMessage = {
  jsonrpc: '2.0';
  id: string;
  result: boolean;
};

export type MinedTransactionNotification = {
  removed?: boolean;
  transaction: {
    accessList: string[];
    blockHash: string;
    blockNumber: string;
    chainId: string;
    from: string;
    gas: string;
    gasPrice: string;
    hash: string;
    input: string;
    maxFeePerGas: string;
    maxPriorityFeePerGas: string;
    nonce: string;
    r: string;
  };
};

export type LogNotification = {
  address: string;
  topics: string[];
  data?: string;
  removed?: boolean;
};

export type EthSubscriptionMessage = {
  jsonrpc: '2.0';
  method: 'eth_subscription';
  params: {
    subscription: string;
    result: MinedTransactionNotification | LogNotification;
  };
};

export type AlchemySocketServerMessage =
  | EthSubscribeResultMessage
  | EthUnsubscribeResultMessage
  | EthSubscriptionMessage;

export type AlchemyGetTokenAssetsResponse = {
  jsonrpc: '2.0';
  id: number;
  result: {
    address: string;
    tokenBalances: {
      contractAddress: string;
      tokenBalance: string;
    }[];
  };
};

export type AlchemyGetTokenAssetResponse = {
  jsonrpc: '2.0';
  id: number;
  result: {
    name: string;
    symbol: string;
    decimals: number;
    logo: string;
  };
};

export type AlchemyNftImage = {
  cachedUrl?: string;
  thumbnailUrl?: string;
  contentType?: string;
  originalUrl?: string;
};

export type AlchemyNftContract = {
  address: string;
  name?: string;
  symbol?: string;
  totalSupply?: string;
  tokenType: EvmNftInterface;
};

export type AlchemyOwnedNft = {
  contract: AlchemyNftContract;
  tokenId: string;
  tokenType: EvmNftInterface;
  name?: string;
  description?: string;
  image: AlchemyNftImage;
  raw: {
    tokenUri?: string;
    metadata?: {
      attributes?: {
        value: string;
        trait_type: string;
      }[];
    };
    error?: string | null;
  };
  balance: string;
};

export type AlchemyNftsForOwnerResponse = {
  ownedNfts: AlchemyOwnedNft[];
  totalCount: number;
  pageKey?: string | null;
};

export type AlchemyAssetChange = {
  changes: {
    amount: string;
    assetType: 'NATIVE' | 'ERC20' | 'ERC721' | 'ERC1155';
    changeType: 'TRANSFER';
    contractAddress: string | null;
    decimals: number;
    from: string;
    logo: string;
    name: string;
    rawAmount: string;
    symbol: string;
    to: string;
    tokenId: string | null;
  }[];
  error: string | null;
  gasUsed: string;
};

export type AlchemyAssetChangesResponse = {
  jsonrpc: '2.0';
  id: number;
  result: AlchemyAssetChange;
};

export type EvmTokenOperation = {
  isSwap: true;
  assets: string[];
  swap: BaseApiSwapHistoryItem;
} | {
  isSwap: false;
  assets: string[];
  transfer: BaseApiTransaction;
};
