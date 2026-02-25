import type {
  Address,
  getCompiledTransactionMessageDecoder,
  GetTransactionApi,
  MessagePartialSigner,
  TransactionPartialSigner,
} from '@solana/kit';

import type { BaseApiSwapHistoryItem, BaseApiTransaction } from '../../types';

export type SolanaSPLTokenGrouping = {
  group_key: 'collection';
  group_value: string;
  verified: boolean;
  collection_metadata: {
    name: string;
    symbol: string;
    image: string;
    description: string;
    external_url: string;
  };
};

export type SolanaSPLToken = {
  interface: 'FungibleToken' | 'MplCoreAsset' | 'ProgrammableNFT' | 'V1_NFT';
  id: string;
  content: {
    $schema: string;
    json_uri: string;
    files: [
      {
        uri: string;
        cdn_uri: string;
        mime: string;
      },
    ];
    metadata: {
      attributes?: {
        value: string;
        trait_type: string;
      }[];
      description: string;
      name: string;
      symbol: string;
      token_standard: string;
    };
    links: {
      image: string;
    };
  };
  authorities: [
    {
      address: string;
      scopes: string[];
    },
  ];
  compression: {
    eligible: boolean;
    compressed: boolean;
    data_hash: string;
    creator_hash: string;
    asset_hash: string;
    tree: string;
    seq: number;
    leaf_id: number;
  };
  grouping: SolanaSPLTokenGrouping[];
  royalty: {
    royalty_model: string;
    target: string | null;
    percent: number;
    basis_points: number;
    primary_sale_happened: boolean;
    locked: boolean;
  };
  creators: [
    {
      address: string;
      share: number;
      verified: boolean;
    },
  ];
  ownership: {
    frozen: boolean;
    delegated: boolean;
    delegate: string | null;
    ownership_model: string;
    owner: string;
  };
  supply: number | null;
  mutable: boolean;
  burnt: boolean;
  token_info: {
    token_accounts: [
      {
        address: string;
        balance: number;
      },
    ];
    balance: number;
    supply: number;
    decimals: number;
    token_program: string;
    associated_token_address: string;

    price_info?: {
      price_per_token: number;
      total_price: number;
      currency: string;
    };
    mint_authority?: string;
  };
};

export type SolanaSPLTokensByAddressRaw = {
  jsonrpc: '2.0';
  result: {
    last_indexed_slot: number;
    total: number;
    limit: number;
    page: number;
    items: SolanaSPLToken[];
    nativeBalance?: {
      lamports: number;
      price_per_sol: number;
      total_price: number;
    };
  };
  id: string;
};

export type SolanaSPLTokenByAddressRaw = {
  jsonrpc: '2.0';
  result: SolanaSPLToken & { last_indexed_slot: number };
  id: string;
};

export type SolanaParsedInstruction = {
  accounts: string[];
  data: string;
  programId: string;
  innerInstructions: {
    accounts: string[];
    data: string;
    programId: string;
  }[];
};

export type SolanaParsedTransaction = {
  description: string;
  type: string;
  source: string;
  fee: number;
  feePayer: string;
  signature: string;
  slot: number;
  timestamp: number;
  tokenTransfers: {
    fromTokenAccount: string;
    toTokenAccount: string;
    fromUserAccount: string;
    toUserAccount: string;
    tokenAmount: number;
    mint: string;
    tokenStandard: 'Fungible' | 'ProgrammableNonFungible';
  }[];
  nativeTransfers: {
    fromUserAccount: string;
    toUserAccount: string;
    amount: number;
  }[];
  accountData: {
    account: string;
    nativeBalanceChange: number;
    tokenBalanceChanges: {
      userAccount: string;
      tokenAccount: string;
      rawTokenAmount: {
        tokenAmount: string;
        decimals: number;
      };
      mint: string;
    }[];
  }[];
  transactionError: Record<string, any> | null;
  instructions: SolanaParsedInstruction[];
  lighthouseData: null; // ??
  events: {
    compressed?: [
      {
        type: string;
        treeId: string;
        leafIndex: number;
        seq: number;
        assetId: string;
        instructionIndex: number;
        innerInstructionIndex: null;
        newLeafOwner: string | null;
        oldLeafOwner: string | null;
        newLeafDelegate: string | null;
        oldLeafDelegate: string | null;
        treeDelegate: string | null;
        metadata: null; // ??
        updateArgs: null; // ??
      },
    ];
    nft?: {
      description: string;
      type: string;
      source: string;
      amount: number;
      fee: number;
      feePayer: string;
      signature: string;
      slot: number;
      timestamp: number;
      saleType: string;
      buyer: string;
      seller: string;
      staker: string;
      nfts: [
        {
          mint: string;
          tokenStandard: string;
        },
      ];
    };
    swap?: {
      nativeInput: {
        account: string;
        amount: string;
      } | null;
      nativeOutput: {
        account: string;
        amount: string;
      } | null;
      tokenInputs: [
        {
          userAccount: string;
          tokenAccount: string;
          rawTokenAmount: {
            tokenAmount: string;
            decimals: number;
          };
          mint: string;
        },
      ];
      tokenOutputs: [
        {
          userAccount: string;
          tokenAccount: string;
          rawTokenAmount: {
            tokenAmount: string;
            decimals: number;
          };
          mint: string;
        },
      ];
      nativeFees: []; // ??
      tokenFees: []; // ??
      innerSwaps: []; // ??
    };
  };
};

export type SolanaTransaction = ReturnType<GetTransactionApi['getTransaction']>;

type SolanaInnerIntrution = {
  index: number;
  instructions: SolanaInstruction[];
};

type SolanaTokenBalance = {
  accountIndex: number;
  mint: string;
  owner: string;
  programId: string;
  uiTokenAmount: {
    amount: string;
    decimals: number;
    uiAmount: number;
    uiAmountString: string;
  };
};

export type SolanaInstructionRaw = {
  accounts: string[];
  data: string;
  programId: string;
  stackHeight: number;
};

export type SolanaInstructionParsed = {
  parsed: {
    info: {
      account: string;
      mint: string;
      source: string;
      systemProgram: string;
      tokenProgram: string;
      wallet: string;
    };
    type: string;
  };
  program: string;
  programId: string;
  stackHeight: number;
};

export type SolanaInstruction = SolanaInstructionRaw | SolanaInstructionParsed;

export type SolanaTransactionEmulationResult = {
  accounts: string[] | null;
  err: null;
  fee: number;
  innerInstructions: SolanaInnerIntrution[];
  loadedAccountsDataSize: number;
  loadedAddresses: {
    readonly: string[];
    writable: string[];
  };
  logs: string[];
  postBalances: number[];
  postTokenBalances: SolanaTokenBalance[];
  preBalances: number[];
  preTokenBalances: SolanaTokenBalance [];
  replacementBlockhash: {
    blockhash: string;
    lastValidBlockHeight: number;
  };
  returnData: null;
  unitsConsumed: null;
};

export type SolanaTransactionEmulationResultRaw = {
  jsonrpc: '2.0';
  result: {
    context: {
      apiVersion: string;
      slot: number;
    };
    value: SolanaTransactionEmulationResult;
  };
  id: string;
};

export type SolanaCompiledTransaction = ReturnType<ReturnType<typeof getCompiledTransactionMessageDecoder>['decode']>;

export type SolanaTokenOperation = {
  isSwap: true;
  assets: string[];
  swap: BaseApiSwapHistoryItem;
} | {
  isSwap: false;
  assets: string[];
  transfer: BaseApiTransaction;
};

export type SolanaAssetProofRaw = {
  jsonrpc: '2.0';
  result: SolanaAssetProof;
  id: '1';
};

export type SolanaAssetProof = {
  last_indexed_slot: number;
  root: string;
  proof: string[];
  node_index: number;
  leaf: string;
  tree_id: string;
};
export type SubscriptionNotification = {
  jsonrpc: '2.0';
  result: number;
  id: string;
  // Use undefineds to make TS type-discrimination work
  params: undefined;
  method: undefined;
};

export type AccountStateChangeSocketMessage = {
  jsonrpc: '2.0';
  method: 'accountNotification';
  params: {
    result: {
      context: {
        slot: number;
      };
      value: {
        lamports: number;
        data: [
          string,
          'base64',
        ];
        owner: string;
        executable: boolean;
        rentEpoch: number;
        space: number;
      };
    };
    subscription: number;
  };
};

export type TokenBalanceChangeSocketMessage = {
  jsonrpc: '2.0';
  method: 'programNotification';
  params: {
    result: {
      context: {
        slot: number;
      };
      value: {
        pubkey: string;
        account: {
          lamports: number;
          data: {
            program: string;
            parsed: {
              info: {
                isNative: boolean;
                mint: string;
                owner: string;
                state: string;
                tokenAmount: {
                  amount: string;
                  decimals: number;
                  uiAmount: number;
                  uiAmountString: string;
                };
              };
              type: string;
            };
            space: number;
          };
          owner: string;
          executable: boolean;
          rentEpoch: number;
          space: number;
        };
      };
    };
    subscription: number;
  };
};

export type AccountLogsSocketMessage = {
  jsonrpc: '2.0';
  method: 'logsNotification';
  params: {
    result: {
      context: {
        slot: number;
      };
      value: {
        signature: string;
        err: string | null; // ??
        logs: string[];
      };
    };
    subscription: 24040;
  };
};

export type ServerSocketMessage =
  | SubscriptionNotification
  | AccountStateChangeSocketMessage
  | TokenBalanceChangeSocketMessage
  | AccountLogsSocketMessage;

export type AccountStateChangeSubMessage = {
  jsonrpc: '2.0';
  id: string;
  method: 'accountSubscribe';
  params: [
    string,
    {
      encoding: 'jsonParsed';
      commitment: 'confirmed';
    },
  ];
};

export type AccountTokensSubMessage = {
  jsonrpc: '2.0';
  id: string;
  method: 'programSubscribe';
  params: [
    string,
    {
      encoding: 'jsonParsed';
      commitment: 'confirmed';
      filters: [
        {
          memcmp: {
            offset: 32;
            bytes: string;
          };
        },
      ];
    },
  ];
};

export type AccountLogsSubMessage = {
  jsonrpc: '2.0';
  id: string;
  method: 'logsSubscribe';
  params: [
    {
      mentions: [string];
    },
    {
      commitment: string;
    },
  ];
};

// Use RPC-method with random payload as ping
export type PingMessage = {
  jsonrpc: '2.0';
  id: string;
  method: 'ping';
};

export type UnsubscribeMethod = 'accountUnsubscribe' | 'programUnsubscribe' | 'logsUnsubscribe';

export type UnsubscribeMessage = {
  jsonrpc: '2.0';
  id: string;
  method: UnsubscribeMethod;
  params: [
    number,
  ];
};

export type ClientSocketMessage =
  | AccountStateChangeSubMessage
  | AccountTokensSubMessage
  | AccountLogsSubMessage
  | PingMessage
  | UnsubscribeMessage;

// Mimic @solana/kit signer type
export type SolanaKeyPairSigner = MessagePartialSigner<string> & TransactionPartialSigner<string> & {
  readonly address: Address;
  readonly publicKeyBytes: Uint8Array;
  readonly secretKey: Uint8Array;
};
