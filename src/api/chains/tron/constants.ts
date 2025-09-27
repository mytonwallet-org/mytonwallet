import { TRON_MAINNET_API_URL, TRON_TESTNET_API_URL } from '../../../config';

export const TRON_GAS = {
  transferTrc20Estimated: 28_214_970n,
};

export const ONE_TRX = 1_000_000n;

export const NETWORK_CONFIG = {
  mainnet: {
    apiUrl: TRON_MAINNET_API_URL,
    usdtAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  },
  testnet: {
    apiUrl: TRON_TESTNET_API_URL,
    usdtAddress: 'TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs',
  },
};
