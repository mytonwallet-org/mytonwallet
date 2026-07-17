/*
 * This file must be imported dynamically via import().
 * This is needed to reduce the app size when Ledger is not used.
 *
 * This file is responsible only for common Ledger connection. Chain-specific logic is implemented in the API.
 */

import type Transport from '@ledgerhq/hw-transport';
import TransportWebHID from '@ledgerhq/hw-transport-webhid';
import TransportWebUSB from '@ledgerhq/hw-transport-webusb';

import type { LedgerTransport } from './types';

import { logDebug, logDebugError } from '../logs';
import { pause } from '../schedulers';
import { ATTEMPTS, PAUSE } from './constants';

let transport: TransportWebHID | TransportWebUSB | undefined;
let currentLedgerTransport: LedgerTransport | undefined;
let transportSupport: {
  hid: boolean;
  webUsb: boolean;
} | undefined;

export async function detectAvailableTransports() {
  const [hid, webUsb] = await Promise.all([
    TransportWebHID.isSupported(),
    TransportWebUSB.isSupported(),
  ]);

  logDebug('LEDGER TRANSPORTS', { hid, webUsb });

  transportSupport = { hid, webUsb };

  return {
    isUsbAvailable: hid || webUsb,
  };
}

/**
 * Connects the Ledger itself. To ensure the chain's Ledger app is ready, use the `waitForLedgerApp` API method.
 */
export async function connectLedger(preferredTransport?: LedgerTransport) {
  const support = await getTransportSupport();

  if (preferredTransport) currentLedgerTransport = preferredTransport;

  try {
    switch (currentLedgerTransport) {
      // Bluetooth (web-ble) is not implemented yet; add a `case 'bluetooth'` here when it is
      case 'usb':
      default:
        if (support.hid) {
          transport = await connectWebHID();
        } else if (support.webUsb) {
          transport = await connectWebUsb();
        }
        break;
    }

    if (!transport) {
      logDebugError('connectLedger: HID and WebUSB are not supported');
      return false;
    }

    return true;
  } catch (err) {
    logDebugError('connectLedger', err);
    return false;
  }
}

export async function disconnectLedger() {
  const activeTransport = transport;
  transport = undefined;
  currentLedgerTransport = undefined;

  try {
    await activeTransport?.close();
  } catch (err) {
    logDebugError('disconnectLedger', err);
  }
}

async function connectWebHID() {
  for (let i = 0; i < ATTEMPTS; i++) {
    const [device] = await TransportWebHID.list();

    if (!device) {
      await TransportWebHID.create();
      await pause(PAUSE);
      continue;
    }

    if (device.opened) {
      return new TransportWebHID(device);
    } else {
      return TransportWebHID.open(device);
    }
  }

  throw new Error('Failed to connect');
}

async function connectWebUsb() {
  for (let i = 0; i < ATTEMPTS; i++) {
    const [device] = await TransportWebUSB.list();

    if (!device) {
      await TransportWebUSB.create();
      await pause(PAUSE);
      continue;
    }

    if (device.opened) {
      return (await TransportWebUSB.openConnected()) ?? (await TransportWebUSB.request());
    } else {
      return TransportWebUSB.open(device);
    }
  }

  throw new Error('Failed to connect');
}

async function getTransportSupport() {
  // Ensure transports support is detected lazily if missing
  if (!transportSupport) {
    await detectAvailableTransports();
  }

  return transportSupport!;
}

export function getTransportOrFail(): Transport {
  if (!transport) {
    throw new Error('Ledger transport is not initialized'); // Run `connectLedger` to initialize
  }
  return transport;
}
