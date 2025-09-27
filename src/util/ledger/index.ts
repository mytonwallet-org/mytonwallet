/*
 * This file must be imported dynamically via import().
 * This is needed to reduce the app size when Ledger is not used.
 *
 * This file is responsible only for common Ledger connection. Chain-specific logic is implemented in the API.
 */

import type Transport from '@ledgerhq/hw-transport';
import TransportWebHID from '@ledgerhq/hw-transport-webhid';
import TransportWebUSB from '@ledgerhq/hw-transport-webusb';
import type { HIDTransport } from '@mytonwallet/capacitor-usb-hid';
import type { ICapacitorUSBDevice } from '@mytonwallet/capacitor-usb-hid/dist/esm/definitions';

import type BleTransport from '../../lib/ledger-hw-transport-ble/BleTransport';
import type { LedgerTransport } from './types';

import { IS_CAPACITOR } from '../../config';
import { logDebug, logDebugError } from '../logs';
import { pause } from '../schedulers';
import { IS_ANDROID_APP } from '../windowEnvironment';
import { ATTEMPTS, DEVICE_DETECT_ATTEMPTS, PAUSE } from './constants';

type BleConnectorClass = typeof import('./bleConnector').BleConnector;
type HIDTransportClass = typeof import('@mytonwallet/capacitor-usb-hid/dist/esm').HIDTransport;
type ListLedgerDevicesFunction = typeof import('@mytonwallet/capacitor-usb-hid/dist/esm').listLedgerDevices;

let transport: TransportWebHID | TransportWebUSB | BleTransport | HIDTransport | undefined;
let transportSupport: {
  hid: boolean;
  webUsb: boolean;
  bluetooth: boolean;
} | undefined;
let currentLedgerTransport: LedgerTransport | undefined;

let hidImportPromise: Promise<{
  transport: HIDTransportClass;
  listLedgerDevices: ListLedgerDevicesFunction;
}> | undefined;
let bleImportPromise: Promise<BleConnectorClass> | undefined;
let BleConnector: BleConnectorClass;
let MtwHidTransport: HIDTransportClass;
let listLedgerDevices: ListLedgerDevicesFunction;

async function ensureBleConnector() {
  if (!IS_CAPACITOR) return undefined;

  if (!bleImportPromise) {
    bleImportPromise = import('./bleConnector').then((module) => {
      return module.BleConnector;
    });
    BleConnector = await bleImportPromise;
  }

  return bleImportPromise;
}

async function ensureHidTransport() {
  if (!IS_ANDROID_APP) return undefined;

  if (!hidImportPromise) {
    hidImportPromise = import('@mytonwallet/capacitor-usb-hid/dist/esm').then((module) => {
      return {
        transport: module.HIDTransport,
        listLedgerDevices: module.listLedgerDevices,
      };
    });
    const result = await hidImportPromise;
    MtwHidTransport = result.transport;
    listLedgerDevices = result.listLedgerDevices;
  }

  return hidImportPromise;
}

void ensureBleConnector();
void ensureHidTransport();

export async function detectAvailableTransports() {
  await ensureBleConnector();
  await ensureHidTransport();
  const [hid, bluetooth, webUsb] = await Promise.all([
    IS_ANDROID_APP ? MtwHidTransport.isSupported() : TransportWebHID.isSupported(),
    BleConnector ? BleConnector.isSupported() : false,
    TransportWebUSB.isSupported(),
  ]);

  logDebug('LEDGER TRANSPORTS', { hid, bluetooth, webUsb });

  transportSupport = { hid, bluetooth, webUsb };

  return {
    isUsbAvailable: hid || webUsb,
    isBluetoothAvailable: bluetooth,
  };
}

export async function hasUsbDevice() {
  const support = await getTransportSupport();

  if (support.hid) {
    return IS_ANDROID_APP
      ? await hasCapacitorHIDDevice()
      : await hasWebHIDDevice();
  }

  if (support.webUsb) {
    return await hasWebUsbDevice();
  }

  return false;
}

export function openSystemBluetoothSettings() {
  if (!BleConnector) return;
  void BleConnector.openSettings();
}

/**
 * Connects the Ledger itself. To ensure the chain's Ledger app is ready, use the `waitForLedgerApp` API method.
 */
export async function connectLedger(preferredTransport?: LedgerTransport) {
  const support = await getTransportSupport();

  if (preferredTransport) currentLedgerTransport = preferredTransport;

  // Note: if you call transport?.close() here, the Bluetooth transport won't work as expected. For example, if TON App
  // is closed in the middle of an operation, the following operations will hang indefinitely.

  try {
    switch (currentLedgerTransport) {
      case 'bluetooth':
        transport = await connectBLE();
        break;

      case 'usb':
      default:
        if (support.hid) {
          transport = await connectHID();
        } else if (support.webUsb) {
          transport = await connectWebUsb();
        }
        break;
    }

    if (!transport) {
      logDebugError('connectLedger: BLE and/or HID are not supported');
      return false;
    }

    return true;
  } catch (err) {
    logDebugError('connectLedger', err);
    return false;
  }
}

function connectHID() {
  if (IS_ANDROID_APP) {
    return connectCapacitorHID();
  }

  return connectWebHID();
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

async function connectCapacitorHID(): Promise<HIDTransport> {
  for (let i = 0; i < ATTEMPTS; i++) {
    const [device] = await listLedgerDevices();

    if (!device) {
      await pause(PAUSE);
      continue;
    }

    try {
      return await Promise.race([
        MtwHidTransport.open(device),
        new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error()), 1000);
        }),
      ]);
    } catch (error) {
      await pause(PAUSE);
    }
  }

  throw new Error('Failed to connect');
}

async function connectBLE(): Promise<BleTransport> {
  if (!BleConnector) {
    throw new Error('BLE is not supported on this device.');
  }

  const connection = await BleConnector.connect();
  return connection.bleTransport;
}

async function tryDetectDevice(
  listDeviceFn: () => Promise<ICapacitorUSBDevice[]>,
  createTransportFn?: () => Promise<unknown> | void,
) {
  try {
    for (let i = 0; i < DEVICE_DETECT_ATTEMPTS; i++) {
      const [device] = await listDeviceFn();
      if (!device) {
        if (createTransportFn) await createTransportFn();
        await pause(PAUSE);
        continue;
      }

      return true;
    }
  } catch (err: any) {
    logDebugError('tryDetectDevice', err);
  }

  return false;
}

function hasWebHIDDevice() {
  return tryDetectDevice(() => TransportWebHID.list(), () => TransportWebHID.create());
}
function hasWebUsbDevice() {
  return tryDetectDevice(() => TransportWebUSB.list(), () => TransportWebUSB.create());
}
function hasCapacitorHIDDevice() {
  return tryDetectDevice(listLedgerDevices);
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
