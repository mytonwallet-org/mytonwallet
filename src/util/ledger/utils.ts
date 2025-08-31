import type { ApiNetwork, ApiTonWallet } from '../../api/types';

import { WORKCHAIN, Workchain } from '../../api/chains/ton/constants';

const BROKEN_CONNECTION_ERRORS = new Set(['DisconnectedDeviceDuringOperation', 'TransportRaceCondition']);

export function getLedgerAccountPathByWallet(network: ApiNetwork, wallet: ApiTonWallet, workchain?: Workchain) {
  return getLedgerAccountPathByIndex(wallet.index, network !== 'mainnet', workchain);
}

export function getLedgerAccountPathByIndex(index: number, isTestnet: boolean, workchain = WORKCHAIN) {
  const network = isTestnet ? 1 : 0;
  const chain = workchain === Workchain.MasterChain ? 255 : 0;
  return [44, 607, network, chain, index, 0];
}

export function isLedgerConnectionBroken(error: string) {
  return BROKEN_CONNECTION_ERRORS.has(error);
}
