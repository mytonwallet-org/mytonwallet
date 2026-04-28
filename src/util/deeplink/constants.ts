import { IS_GRAM_WALLET } from '../../config';

export const TON_PROTOCOL = 'ton://';
export const TONCONNECT_PROTOCOL = 'tc://';
export const TONCONNECT_PROTOCOL_SELF = IS_GRAM_WALLET ? 'gramwallet-tc://' : 'mytonwallet-tc://';
export const SELF_PROTOCOL = IS_GRAM_WALLET ? 'gramwallet://' : 'mtw://';
export const SELF_UNIVERSAL_URLS = IS_GRAM_WALLET
  ? ['https://gramwallet.io']
  : ['https://my.tt', 'https://go.mytonwallet.org'];
export const TONCONNECT_UNIVERSAL_URL = IS_GRAM_WALLET
  ? 'https://gramwallet.io/tonconnect'
  : 'https://connect.mytonwallet.org';
export const CHECKIN_URL = 'https://checkin.mytonwallet.org';
export const WALLETCONNECT_PROTOCOL = 'wc:';
