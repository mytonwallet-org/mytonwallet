import { TRC20_USDT_MAINNET, TRC20_USDT_TESTNET, TRON_MAINNET_API_URL, TRON_TESTNET_API_URL } from '../../../config';

export const TRON_GAS = {
  transferTrc20Estimated: 28_214_970n,
};

export const ONE_TRX = 1_000_000n;

export const NETWORK_CONFIG = {
  mainnet: {
    apiUrl: TRON_MAINNET_API_URL,
    usdtAddress: TRC20_USDT_MAINNET.tokenAddress,
  },
  testnet: {
    apiUrl: TRON_TESTNET_API_URL,
    usdtAddress: TRC20_USDT_TESTNET.tokenAddress,
  },
};
