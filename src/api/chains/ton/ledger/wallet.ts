import type { ApiHardwareError, ApiNetwork, ApiTonWallet } from '../../../types';

import { LEDGER_DEFAULT_WALLET_VERSION } from '../constants';
import { getLedgerWalletParams, handleLedgerTonError, type PossibleWalletVersion, tonTransport } from './utils';

/**
 * Takes about 170ms on Ledger Nano X connected to Chrome on macOS and 212ms on Ledger Nano X connected to iPhone.
 * There is no need to call this function in parallel, because the transport will force them to be sequential anyway.
 */
export async function getLedgerTonWallet(
  network: ApiNetwork,
  accountIndex: number,
): Promise<ApiTonWallet | { error: ApiHardwareError }> {
  try {
    const version = LEDGER_DEFAULT_WALLET_VERSION;
    const { address, publicKey } = await tonTransport.getAddress(
      ...getLedgerWalletParams(network, accountIndex, version),
    );

    return {
      index: accountIndex,
      address,
      publicKey: publicKey.toString('hex'),
      version,
    };
  } catch (err) {
    return handleLedgerTonError(err);
  }
}

export async function verifyLedgerTonAddress(
  network: ApiNetwork,
  wallet: ApiTonWallet,
): Promise<string | { error: ApiHardwareError }> {
  try {
    const { address } = await tonTransport.validateAddress(
      ...getLedgerWalletParams(network, wallet.index, wallet.version as PossibleWalletVersion),
    );
    return address;
  } catch (err) {
    return handleLedgerTonError(err);
  }
}
