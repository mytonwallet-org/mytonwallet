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

type BaseCheckParams = {
  id: number;
  type: 'coin' | 'nft';
  contractAddress: string;
  status: CheckStatus;
  isInvoice?: boolean;
  isCurrentUserSender?: boolean;
  comment?: string;
  txId?: string;
  receiverAddress?: string;
  failureReason?: string;
};

type StandardCheckParams = {
  salt?: string;
  provider: 'tma';
  chatInstance?: string;
  username?: string;
};

type JwtCheckParams = {
  salt: string;
  provider: 'email' | 'google' | 'apple' | 'facebook' | 'twitch' | 'discord' | 'twitter';
  targetHash: string;
  targetHash3: string;
  targetHint: string;
};

type CoinCheckParams = {
  type: 'coin';
  amount: number;
  symbol: TokenSymbol;
  minterAddress?: string;
  decimals: number;
};

type NftCheckParams = {
  type: 'nft';
  nftInfo: NftInfo;
};

export type ApiStandardCoinCheck = BaseCheckParams & StandardCheckParams & CoinCheckParams;
export type ApiStandardNftCheck = BaseCheckParams & StandardCheckParams & NftCheckParams;
export type ApiJwtCoinCheck = BaseCheckParams & JwtCheckParams & CoinCheckParams;
export type ApiJwtNftCheck = BaseCheckParams & JwtCheckParams & NftCheckParams;

export type ApiCoinCheck = ApiStandardCoinCheck | ApiJwtCoinCheck;
export type ApiNftCheck = ApiStandardNftCheck | ApiJwtNftCheck;

export type ApiStandardCheck = ApiStandardCoinCheck | ApiStandardNftCheck;
export type ApiJwtCheck = ApiJwtCoinCheck | ApiJwtNftCheck;

export type ApiCheck = ApiStandardCoinCheck | ApiStandardNftCheck | ApiJwtCoinCheck | ApiJwtNftCheck;

export interface ApiWallet {
  connectedAddress?: string;
}
