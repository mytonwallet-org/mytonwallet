import { BleClient } from '@capacitor-community/bluetooth-le';
import type { Subscription as TransportSubscription } from '@ledgerhq/hw-transport';
import { v4 as uuid } from 'uuid';
import type { BleDevice } from '@capacitor-community/bluetooth-le/dist/esm/definitions';

import { IS_CAPACITOR } from '../../config';
import BleTransport from '../../lib/ledger-hw-transport-ble/BleTransport';
import { logDebug, logDebugError } from '../logs';
import { pause } from '../schedulers';
import { IS_ANDROID, IS_IOS } from '../windowEnvironment';
import { DEVICE_DETECT_ATTEMPTS, PAUSE } from './constants';

interface ScannedDevice {
  identifier: string;
  device: BleDevice;
}

export interface LedgerConnection {
  device: BleDevice;
  bleTransport: BleTransport;
}

let isBleInitialized = false;
let bleInitializationPromise: Promise<void> | undefined;

let listeningSubscription: TransportSubscription | undefined;

let scannedDevices: ScannedDevice[] = [];
let pairedDevice: LedgerConnection | undefined;
let onLedgerConnected: ((connection: LedgerConnection) => void) | undefined;

function isConnecting() {
  return !!listeningSubscription;
}

function scannedDeviceIsValidYet(scannedDevice: ScannedDevice): boolean {
  if (!scannedDevices.find((it) => it.identifier === scannedDevice.identifier)) {
    // List is already cleared
    return false;
  }

  // A device is already paired
  return !pairedDevice;
}

async function tryConnectingLedgerDevice(scannedDevice: ScannedDevice) {
  try {
    // Check if stopped before retry
    if (!scannedDeviceIsValidYet(scannedDevice)) return;

    const bleTransport = await BleTransport.open(scannedDevice.device);
    // Check if stopped before connection establish
    if (!scannedDeviceIsValidYet(scannedDevice)) return;

    const ledgerConnection = {
      device: scannedDevice.device,
      bleTransport,
    };
    pairedDevice = ledgerConnection;

    bleTransport.disconnectCallback = () => {
      pairedDevice = undefined;
      if (isConnecting()) {
        stop();
        void start();
      }
    };

    setTimeout(() => {
      // Make sure not disconnected yet
      if (pairedDevice?.device.deviceId === ledgerConnection.device.deviceId) {
        onLedgerConnected?.(ledgerConnection);
        stop();
      } else if (isConnecting()) {
        // Unexpectedly, disconnected before calling the callback, restart!
        pairedDevice = undefined;
        stop();
        void start();
      }
    }, 1000);
  } catch (error) {
    setTimeout(() => {
      void tryConnectingLedgerDevice(scannedDevice);
    }, 10000);
  }
}

async function isSupported() {
  if (!IS_CAPACITOR) return false;

  let isEnabled = false;
  try {
    await ensureBleInitialized();
    if (IS_ANDROID) {
      await BleClient.requestEnable();
    }

    isEnabled = await BleClient.isEnabled();
    logDebug('BLE isSupported result', { isEnabled });
  } catch (err: any) {
    logDebugError('Error while checking BLE availability', err);
  }

  return isEnabled;
}

async function start() {
  await ensureBleInitialized();

  listeningSubscription = BleTransport.listen({
    next: (event: { type: string; device?: BleDevice }) => {
      switch (event.type) {
        case 'add':
          if (event.device) {
            if (!event.device.name) return;
            if (scannedDevices.find((it) => it.device.deviceId === event.device?.deviceId)) return;
            const scannedDevice = { identifier: uuid(), device: event.device };
            scannedDevices.push(scannedDevice);
            void tryConnectingLedgerDevice(scannedDevice);
          }
          break;
      }
    },
    error: () => {
      stop();
    },
    complete: () => {
      stop();
    },
  });
}

function stop() {
  scannedDevices = [];
  listeningSubscription?.unsubscribe();
  listeningSubscription = undefined;
}

async function disconnect() {
  stop();
  onLedgerConnected = undefined;

  const connection = pairedDevice;
  pairedDevice = undefined;
  if (!connection) return false;

  connection.bleTransport.disconnectCallback = undefined;
  await BleTransport.disconnectDevice(connection.bleTransport.id, connection.bleTransport.onDisconnect);
  return true;
}

function connect(): Promise<LedgerConnection> {
  return new Promise((resolve) => {
    onLedgerConnected = resolve;
    if (pairedDevice) {
      onLedgerConnected(pairedDevice);
      return;
    }

    if (isConnecting()) return;
    void start();
  });
}

async function openSettings() {
  if (IS_ANDROID) {
    await BleClient.openBluetoothSettings();
  } else if (IS_IOS) {
    await BleClient.openAppSettings();
  }
}

export const BleConnector = {
  isSupported,
  connect,
  disconnect,
  stop,
  openSettings,
};

async function ensureBleInitialized(): Promise<void> {
  if (isBleInitialized) return;
  if (bleInitializationPromise) return bleInitializationPromise;

  bleInitializationPromise = (async () => {
    let attempt = 0;
    let lastError: Error | undefined;

    while (attempt < DEVICE_DETECT_ATTEMPTS && !isBleInitialized) {
      try {
        await BleClient.initialize({
          androidNeverForLocation: true,
        });
        isBleInitialized = true;
        return;
      } catch (err: any) {
        lastError = err;

        logDebugError('BLE initialize attempt failed', err);
        await pause(PAUSE * attempt);
      }

      attempt += 1;
    }

    if (!isBleInitialized) {
      throw lastError ?? new Error('BLE initialize failed');
    }
  })()
    .finally(() => {
      bleInitializationPromise = undefined;
    });

  return bleInitializationPromise;
}
