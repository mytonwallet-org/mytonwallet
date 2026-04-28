import arbitrumBlockchainIcon from '../../assets/blockchain/chain_arbitrum.svg';
import avalancheBlockchainIcon from '../../assets/blockchain/chain_avalanche.svg';
import baseBlockchainIcon from '../../assets/blockchain/chain_base.svg';
import bitcoinBlockchainIcon from '../../assets/blockchain/chain_bitcoin.svg';
import bitcoincashBlockchainIcon from '../../assets/blockchain/chain_bitcoincash.svg';
import bnbBlockchainIcon from '../../assets/blockchain/chain_bnb.svg';
import cardanoBlockchainIcon from '../../assets/blockchain/chain_cardano.svg';
import cosmosBlockchainIcon from '../../assets/blockchain/chain_cosmos.svg';
import dashBlockchainIcon from '../../assets/blockchain/chain_dash.svg';
import dogeBlockchainIcon from '../../assets/blockchain/chain_doge.svg';
import eosBlockchainIcon from '../../assets/blockchain/chain_eos.svg';
import ethereumBlockchainIcon from '../../assets/blockchain/chain_ethereum.svg';
import ethereumclassicBlockchainIcon from '../../assets/blockchain/chain_ethereumclassic.svg';
import hyperliquidBlockchainIcon from '../../assets/blockchain/chain_hyperliquid.svg';
import internetcomputerBlockchainIcon from '../../assets/blockchain/chain_internetcomputer.svg';
import iotaBlockchainIcon from '../../assets/blockchain/chain_iota.svg';
import litecoinBlockchainIcon from '../../assets/blockchain/chain_litecoin.svg';
import monadBlockchainIcon from '../../assets/blockchain/chain_monad.svg';
import moneroBlockchainIcon from '../../assets/blockchain/chain_monero.svg';
import polkadotBlockchainIcon from '../../assets/blockchain/chain_polkadot.svg';
import polygonBlockchainIcon from '../../assets/blockchain/chain_polygon.svg';
import rippleBlockchainIcon from '../../assets/blockchain/chain_ripple.svg';
import solanaBlockchainIcon from '../../assets/blockchain/chain_solana.svg';
import stellarBlockchainIcon from '../../assets/blockchain/chain_stellar.svg';
import tonBlockchainIcon from '../../assets/blockchain/chain_ton.svg';
import tronBlockchainIcon from '../../assets/blockchain/chain_tron.svg';
import zcashBlockchainIcon from '../../assets/blockchain/chain_zcash.svg';

const CHAIN_ICON_MAP: Record<string, string> = {
  avalanche: avalancheBlockchainIcon,
  bitcoin: bitcoinBlockchainIcon,
  bitcoin_cash: bitcoincashBlockchainIcon,
  binance_smart_chain: bnbBlockchainIcon,
  binance_dex: bnbBlockchainIcon,
  cardano: cardanoBlockchainIcon,
  cosmos: cosmosBlockchainIcon,
  dash: dashBlockchainIcon,
  doge: dogeBlockchainIcon,
  eos: eosBlockchainIcon,
  ethereum: ethereumBlockchainIcon,
  ethereum_classic: ethereumclassicBlockchainIcon,
  internet_computer: internetcomputerBlockchainIcon,
  iota: iotaBlockchainIcon,
  litecoin: litecoinBlockchainIcon,
  monero: moneroBlockchainIcon,
  polkadot: polkadotBlockchainIcon,
  ripple: rippleBlockchainIcon,
  solana: solanaBlockchainIcon,
  stellar: stellarBlockchainIcon,
  ton: tonBlockchainIcon,
  tron: tronBlockchainIcon,
  zcash: zcashBlockchainIcon,
  base: baseBlockchainIcon,
  polygon: polygonBlockchainIcon,
  bnb: bnbBlockchainIcon,
  arbitrum: arbitrumBlockchainIcon,
  monad: monadBlockchainIcon,
  hyperliquid: hyperliquidBlockchainIcon,
};

export default function getChainNetworkIcon(networkName?: string) {
  if (!networkName) return '';

  return CHAIN_ICON_MAP[networkName] ?? networkName;
}
