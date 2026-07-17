import { findChainConfig } from '../chain';

const NETWORK_NAMES_EXCEPTIONS: Record<string, string> = {
  binance_smart_chain: 'Binance Smart Chain',
  internet_computer: 'Internet Computer',
  ethereum_classic: 'Ethereum Classic',
  bitcoin_cash: 'Bitcoin Cash',
  binance_dex: 'Binance Dex',
  ton: 'TON',
  bitcoin: 'Bitcoin',
  ethereum: 'Ethereum',
  solana: 'Solana',
  tron: 'TRON',
  stellar: 'Stellar',
  doge: 'DOGE',
  eos: 'EOS',
  avalanche: 'Avalanche',
  cardano: 'Cardano',
  monero: 'Monero',
  dash: 'Dash',
  ripple: 'Ripple',
  cosmos: 'Cosmos',
  litecoin: 'Litecoin',
  zcash: 'Zcash',
  polkadot: 'Polkadot',
  iota: 'IOTA',
};

export default function getChainNetworkName(networkName?: string) {
  if (!networkName) return '';

  return findChainConfig(networkName)?.title ?? NETWORK_NAMES_EXCEPTIONS[networkName] ?? networkName;
}
