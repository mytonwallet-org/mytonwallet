/*
 * This file must be imported dynamically via import().
 * This is needed to reduce the app size when Ledger is not used.
 */

import Transport from '@ledgerhq/hw-transport';

import type { ApiLedgerDriver } from '../types';
import { ApiHardwareError } from '../types';

import { IS_AIR_APP } from '../../config';
import { callWindow } from '../../util/windowProvider/connector';

/**
 * Serialization format differs between web/capacitor and native apps:
 *  - Native (AIR) apps: Use hex format (expected by native Ledger library implementations)
 *  - Web/Capacitor apps: Use base64 format (more efficient for browser message passing)
 */
const serializationFormat = IS_AIR_APP ? 'hex' : 'base64';

const BROKEN_CONNECTION_ERRORS = new Set([
  // This error occurs sometimes if the chains' Ledger app is closed during a data transmission with Ledger
  'DisconnectedDeviceDuringOperation',
  // One way to reproduce this error is:
  // 1. Run the app in Capacitor on iOS,
  // 2. Connect Ledger and open TON App,
  // 3. Start the connection in the UI, e.g. by sending a transaction,
  // 4. As soon as the checklist screen appears, exit TON App immediately,
  // 5. Start the connection in the UI again without entering TON App.
  // It happens only sometimes. The error message suggests reconnecting Ledger.
  'TransportRaceCondition',
]);

/**
 * A Ledger's Transport implementation that passes the data to the actual transfer object in the main browser thread
 * (src/util/ledger/index.ts) via postMessage (because actual Ledger transports don't work in worker threads).
 */
class WindowTransport extends Transport {
  /** Use `getDeviceModel()` instead */
  declare deviceModel: never;

  /** The thrown errors may unexpectedly have the default `Error` class. For reliability, check the `name` instead. */
  async exchange(apdu: Buffer) {
    const response = await callWindow('exchangeWithLedger', apdu.toString(serializationFormat));
    return Buffer.from(response, serializationFormat);
  }

  getDeviceModel() {
    return callWindow('getLedgerDeviceModel');
  }
}

/** Connection with Ledger (blockchain-agnostic) */
export const ledgerTransport = new WindowTransport();

export async function getLedgerDeviceInfo() {
  const deviceModel = await ledgerTransport.getDeviceModel();
  const driver: ApiLedgerDriver = 'HID';

  return {
    driver,
    deviceId: deviceModel?.id,
    deviceName: deviceModel?.productName,
  };
}

function isLedgerConnectionBroken(error: unknown) {
  return error instanceof Error && BROKEN_CONNECTION_ERRORS.has(error.name);
}

/** Throws unexpected errors (i.e. caused by mistakes in the app code), and returns expected */
export function handleLedgerCommonError(error: unknown) {
  if (isLedgerConnectionBroken(error)) {
    return { error: ApiHardwareError.ConnectionBroken };
  }

  throw error;
}
