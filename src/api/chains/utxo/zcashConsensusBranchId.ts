import type { ApiNetwork } from '../../types';

type UpgradeActivation = {
  height: number;
  branchId: number;
};

/** Mirrors `CurrentEpochBranchId` from zcash `chainparams` + `upgrades.cpp`. */
const MAINNET_UPGRADES: UpgradeActivation[] = [
  { height: 347500, branchId: 0x5ba81b19 },
  { height: 419200, branchId: 0x76b809bb },
  { height: 653600, branchId: 0x2bb40e60 },
  { height: 903000, branchId: 0xf5b9230b },
  { height: 1046400, branchId: 0xe9ff75a6 },
  { height: 1687104, branchId: 0xc2d6d0b4 },
  { height: 2726400, branchId: 0xc8e71055 },
  { height: 3146400, branchId: 0x4dec4df0 },
  { height: 3364600, branchId: 0x5437f330 },
  { height: 3428143, branchId: 0x37a5165b },
];

const TESTNET_UPGRADES: UpgradeActivation[] = [
  { height: 207500, branchId: 0x5ba81b19 },
  { height: 280000, branchId: 0x76b809bb },
  { height: 584000, branchId: 0x2bb40e60 },
  { height: 903800, branchId: 0xf5b9230b },
  { height: 1028500, branchId: 0xe9ff75a6 },
  { height: 1842420, branchId: 0xc2d6d0b4 },
  { height: 2976000, branchId: 0xc8e71055 },
  { height: 3536500, branchId: 0x4dec4df0 },
  { height: 4052000, branchId: 0x5437f330 },
  { height: 4134000, branchId: 0x37a5165b },
];

const BRANCH_ID_HEX_RE = /^[0-9a-fA-F]{8}$/;

/** Parses `backend.consensus.chaintip` from Blockbook status (ZIP-244 branch id). */
export function parseZcashConsensusBranchIdHex(hex: string | undefined): number | undefined {
  if (!hex || !BRANCH_ID_HEX_RE.test(hex)) {
    return undefined;
  }

  return Number.parseInt(hex, 16);
}

export function getZcashConsensusBranchIdForHeight(network: ApiNetwork, height: number): number {
  if (height < 0) {
    throw new Error('Invalid block height for Zcash consensus branch id');
  }

  const upgrades = network === 'mainnet' ? MAINNET_UPGRADES : TESTNET_UPGRADES;
  let branchId = 0;

  for (const upgrade of upgrades) {
    if (height >= upgrade.height) {
      branchId = upgrade.branchId;
    }
  }

  if (!branchId) {
    throw new Error('Block height is before Overwinter; Zcash v5 transactions are not supported');
  }

  return branchId;
}
