import {
  SOLANA_MAINNET_API_KEY,
  SOLANA_MAINNET_API_URL,
  SOLANA_MAINNET_RPC_URL,
  SOLANA_TESTNET_API_KEY,
  SOLANA_TESTNET_API_URL,
  SOLANA_TESTNET_RPC_URL,
} from '../../../config';

const mainnetQueryString = SOLANA_MAINNET_API_KEY ? `?api-key=${SOLANA_MAINNET_API_KEY}` : '';
const testnetQueryString = SOLANA_TESTNET_RPC_URL ? `?api-key=${SOLANA_TESTNET_API_KEY}` : '';

export const NETWORK_CONFIG = {
  mainnet: {
    rpcUrl: `${SOLANA_MAINNET_RPC_URL}/${mainnetQueryString}`,
    getApiUrl: (path: string) => `${SOLANA_MAINNET_API_URL}${path}/${mainnetQueryString}`,
  },
  testnet: {
    rpcUrl: `${SOLANA_TESTNET_RPC_URL}/${testnetQueryString}`,
    getApiUrl: (path: string) => `${SOLANA_TESTNET_API_URL}${path}/${testnetQueryString}`,
  },
};

export const SOLANA_PROGRAM_IDS = {
  system: [
    '11111111111111111111111111111111',
  ],
  token: [
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', // classic SPL
    'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb', // token-2022
  ],
  ata: [
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL',
  ],
  memo: [
    'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr', // v2
    'Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo', // v1
  ],
  computeBudget: [
    'ComputeBudget111111111111111111111111111111',
  ],
  nft: [
    'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s', // Metaplex legacy
    'CoREENxT6tW1HoK8ypY1SxRMZTcVPm7R94rH4PZNhX7d', // Metaplex Core
    'BGUMAp9Gq7iTEuizy4pqaxsTyUCBK68MDfK752saRPUY', // Metaplex Bubblegum
    'wns1gDLt8fgLcGhWi5MqAqgXpwEP1JftKE9eZnXS1HM', // Wen new standard
  ],
};

export const WSOL_MINT = 'So11111111111111111111111111111111111111112';

export const SOLANA_DERIVATION_PATHS = {
  phantom: `m/44'/501'/0'/0'`,
  trust: `m/44'/501'/0'`,
  default: `m/44'/501'`,
};
