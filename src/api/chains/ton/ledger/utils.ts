import { TransportStatusError } from '@ledgerhq/errors';
import { TonTransport } from '@ton-community/ton-ledger';

import type { ApiNetwork, ApiTonWallet } from '../../../types';
import { ApiHardwareError } from '../../../types';

import { handleLedgerCommonError, ledgerTransport } from '../../../common/ledger';
import { LEDGER_WALLET_VERSIONS, WALLET_IS_BOUNCEABLE, WORKCHAIN, Workchain } from '../constants';

export type PossibleWalletVersion = keyof typeof LEDGER_WALLET_VERSIONS;

export const tonTransport = new TonTransport(ledgerTransport);

export function getLedgerAccountPathByWallet(network: ApiNetwork, wallet: ApiTonWallet, workchain?: Workchain) {
  return getLedgerAccountPathByIndex(wallet.index, network !== 'mainnet', workchain);
}

export function getLedgerAccountPathByIndex(index: number, isTestnet: boolean, workchain = WORKCHAIN) {
  const network = isTestnet ? 1 : 0;
  const chain = getInternalWorkchain(workchain);
  return [44, 607, network, chain, index, 0];
}

function getInternalWorkchain(workchain: Workchain) {
  return workchain === Workchain.MasterChain ? 255 : 0;
}

export function getInternalWalletVersion(version: PossibleWalletVersion) {
  return LEDGER_WALLET_VERSIONS[version];
}

/** Throws unexpected errors (i.e. caused by mistakes in the app code), and returns expected */
export function handleLedgerTonError(error: unknown) {
  if (error instanceof TransportStatusError) {
    // Status code reference: https://github.com/LedgerHQ/app-ton/blob/d3e1edbbc1fcf9a5d6982fbb971f757a83d0aa56/src/sw.h
    switch (error.statusCode) {
      case 0x6985: return { error: ApiHardwareError.RejectedByUser };
      case 0xbd00: return { error: ApiHardwareError.BlindSigningNotEnabled };
      // The limits for Ton Connect proofs are: payload ≤ 128 bytes, domain ≤ 128 bytes, payload + domain ≤ 222 bytes
      case 0xb00b: return { error: ApiHardwareError.ProofTooLarge };
    }
  }

  return handleLedgerCommonError(error);
}

/** Checks whether the current Ledger device is the one that stores the given wallet */
export async function doesLedgerDeviceMatch(network: ApiNetwork, wallet: ApiTonWallet) {
  const { publicKey } = await tonTransport.getAddress(
    ...getLedgerWalletParams(network, wallet.index, wallet.version as PossibleWalletVersion),
  );
  return publicKey.toString('hex') === wallet.publicKey;
}

export function getLedgerWalletParams(network: ApiNetwork, accountIndex: number, walletVersion: PossibleWalletVersion) {
  const isTestnet = network !== 'mainnet';
  const workchain = WORKCHAIN;
  const accountPath = getLedgerAccountPathByIndex(accountIndex, isTestnet, workchain);

  return [accountPath, {
    testOnly: isTestnet,
    chain: getInternalWorkchain(workchain),
    bounceable: WALLET_IS_BOUNCEABLE,
    walletVersion: getInternalWalletVersion(walletVersion),
  }] as const;
}
