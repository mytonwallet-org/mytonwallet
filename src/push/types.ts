interface NftInfo {
  address: string;
  name: string;
  collectionName: string;
  collectionAddress: string;
  imageUrl?: string;
  isTelegramGift: boolean;
  giftAnimationUrl?: string;
}

export type TokenSymbol = 'TON' | 'USDT' | 'MY';
type CheckStatus = 'pending_signature' | 'sending' | 'pending_receive' | 'receiving' | 'received' | 'failed';

export type ApiCheck =
  | {
    id: number;
    type: 'coin';
    contractAddress: string;
    status: CheckStatus;
    isInvoice?: boolean;
    isCurrentUserSender?: boolean;
    amount: number;
    symbol: TokenSymbol;
    minterAddress?: string;
    decimals: number;
    chatInstance?: string;
    username?: string;
    comment?: string;
    txId?: string;
    receiverAddress?: string;
    failureReason?: string;
  }
  | {
    id: number;
    type: 'nft';
    contractAddress: string;
    status: CheckStatus;
    isInvoice?: boolean;
    isCurrentUserSender?: boolean;
    nftInfo: NftInfo;
    chatInstance?: string;
    username?: string;
    comment?: string;
    txId?: string;
    receiverAddress?: string;
    failureReason?: string;
  };

export interface ApiWallet {
  connectedAddress?: string;
}
