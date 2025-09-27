import { StatusCodes, TransportStatusError } from '@ledgerhq/errors';

import type { ApiHardwareError } from '../../../types';

import { ledgerTransport } from '../../../common/ledger';
import { LEDGER_DEFAULT_WALLET_VERSION } from '../constants';
import { DEVICES_WITH_LOCK_DOUBLE_CHECK } from './support';
import { getInternalWalletVersion, getLedgerAccountPathByIndex, handleLedgerTonError, tonTransport } from './utils';

export async function isLedgerTonAppOpen(): Promise<boolean | { error: ApiHardwareError }> {
  try {
    if (!(await tonTransport.isAppOpen())) {
      return false;
    }

    const deviceModel = await ledgerTransport.getDeviceModel();

    if (!deviceModel || DEVICES_WITH_LOCK_DOUBLE_CHECK.has(deviceModel.id)) {
      // Workaround for Ledger Nano S or Nano S Plus, this is a way to check if it is unlocked.
      // There will be an error with code 0x530c.
      await tonTransport.getAddress(getLedgerAccountPathByIndex(0, false), {
        walletVersion: getInternalWalletVersion(LEDGER_DEFAULT_WALLET_VERSION),
      });
    }

    return true;
  } catch (err) {
    if (err instanceof TransportStatusError && (
      err.statusCode === StatusCodes.LOCKED_DEVICE
      || err.statusCode === 0x530c
    )) {
      return false;
    }

    return handleLedgerTonError(err);
  }
}
