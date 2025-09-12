import type Transport from '@ledgerhq/hw-transport';
import TransportWebHID from '@ledgerhq/hw-transport-webhid';
import TransportWebUSB from '@ledgerhq/hw-transport-webusb';
import type { HIDTransport } from '@mytonwallet/capacitor-usb-hid';
import { TonTransport } from '@ton-community/ton-ledger';
import type { ICapacitorUSBDevice } from '@mytonwallet/capacitor-usb-hid/dist/esm/definitions';

import type { ApiNetwork } from '../../api/types';
import type BleTransport from '../../lib/ledger-hw-transport-ble/BleTransport';
import type { PossibleWalletVersion } from './constants';
import type { LedgerTransport, LedgerWalletInfo } from './types';

import { IS_CAPACITOR } from '../../config';
import { callApi } from '../../api';
import { WALLET_IS_BOUNCEABLE } from '../../api/chains/ton/constants';
import { handleServerError } from '../../api/errors';
import { parseAccountId } from '../account';
import { logDebug, logDebugError } from '../logs';
import { pause } from '../schedulers';
import { IS_ANDROID_APP } from '../windowEnvironment';
import {
  ATTEMPTS,
  DEFAULT_WALLET_VERSION,
  DEVICE_DETECT_ATTEMPTS,
  INTERNAL_WORKCHAIN,
  IS_BOUNCEABLE,
  PAUSE,
} from './constants';
import { LedgerWalletVersion } from './constants';
import { getLedgerAccountPathByIndex, getLedgerAccountPathByWallet, isLedgerConnectionBroken } from './utils';

type BleConnectorClass = typeof import('./bleConnector').BleConnector;
type HIDTransportClass = typeof import('@mytonwallet/capacitor-usb-hid/dist/esm').HIDTransport;
type ListLedgerDevicesFunction = typeof import('@mytonwallet/capacitor-usb-hid/dist/esm').listLedgerDevices;

let transport: TransportWebHID | TransportWebUSB | BleTransport | HIDTransport | undefined;
let tonTransport: TonTransport | undefined;
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

function getInternalWalletVersion(version: PossibleWalletVersion) {
  return LedgerWalletVersion[version];
}

export async function importLedgerWallet(network: ApiNetwork, accountIndex: number) {
  const walletInfo = await getLedgerWalletInfo(network, accountIndex);
  return callApi('importLedgerWallet', network, walletInfo);
}

export function openSystemBluetoothSettings() {
  if (!BleConnector) return;
  void BleConnector.openSettings();
}

export async function reconnectLedger() {
  try {
    if (await tonTransport?.isAppOpen()) {
      return true;
    }
  } catch {
    // Do nothing
  }

  const isLedgerConnected = await connectLedger();
  if (!isLedgerConnected) return false;

  try {
    return await waitLedgerTonApp();
  } catch (err: any) {
    if (isLedgerConnectionBroken(err.name)) {
      return reconnectLedger();
    }

    throw err;
  }
}

export async function connectLedger(preferredTransport?: LedgerTransport) {
  const support = await getTransportSupport();

  if (preferredTransport) currentLedgerTransport = preferredTransport;

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

    tonTransport = new TonTransport(transport);
    return true;
  } catch (err) {
    logDebugError('connectLedger', err);
    return false;
  }
}

async function waitLedgerTonAppDeadline(): Promise<boolean> {
  await pause(PAUSE * ATTEMPTS);
  return false;
}

async function checkTonApp() {
  for (let i = 0; i < ATTEMPTS; i++) {
    try {
      const isTonOpen = await tonTransport?.isAppOpen();

      if (isTonOpen) {
        if (transport?.deviceModel?.id.startsWith('nanoS')) {
          // Workaround for Ledger Nano S or Nano S Plus, this is a way to check if it is unlocked.
          // There will be an error with code 0x530c.
          await tonTransport?.getAddress(getLedgerAccountPathByIndex(0, false), {
            walletVersion: LedgerWalletVersion[DEFAULT_WALLET_VERSION],
          });
        }

        return true;
      }
    } catch (err: any) {
      if (isLedgerConnectionBroken(err.name)) {
        tonTransport = undefined;
        throw err;
      }
      if (!err?.message.includes('0x530c')) {
        logDebugError('waitLedgerTonApp', err);
      }
    }

    await pause(PAUSE);
  }

  return false;
}

export function waitLedgerTonApp() {
  return Promise.race([
    checkTonApp(),
    waitLedgerTonAppDeadline(),
  ]);
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

export async function getNextLedgerWallets(
  network: ApiNetwork,
  lastExistingIndex = -1,
  alreadyImportedAddresses: string[] = [],
) {
  const result: LedgerWalletInfo[] = [];
  let index = lastExistingIndex + 1;

  try {
    while (true) {
      const walletInfo = await getLedgerWalletInfo(network, index);

      if (alreadyImportedAddresses.includes(walletInfo.address)) {
        index += 1;
        continue;
      }

      if (walletInfo.balance !== 0n) {
        result.push(walletInfo);
        index += 1;
        continue;
      }

      if (!result.length) {
        result.push(walletInfo);
      }

      return result;
    }
  } catch (err) {
    return handleServerError(err);
  }
}

async function getLedgerWalletInfo(network: ApiNetwork, accountIndex: number): Promise<LedgerWalletInfo> {
  const isTestnet = network === 'testnet';
  const { address, publicKey } = await getLedgerWalletAddress(accountIndex, isTestnet);
  const balance = (await callApi('getWalletBalance', 'ton', network, address))!;

  return {
    index: accountIndex,
    address,
    publicKey: publicKey.toString('hex'),
    balance,
    version: DEFAULT_WALLET_VERSION,
    driver: 'HID',
    deviceId: transport!.deviceModel?.id,
    deviceName: transport!.deviceModel?.productName,
  };
}

function getLedgerWalletAddress(index: number, isTestnet: boolean) {
  const path = getLedgerAccountPathByIndex(index, isTestnet);

  return tonTransport!.getAddress(path, {
    testOnly: isTestnet,
    chain: INTERNAL_WORKCHAIN,
    bounceable: WALLET_IS_BOUNCEABLE,
    walletVersion: LedgerWalletVersion[DEFAULT_WALLET_VERSION],
  });
}

export async function verifyAddress(accountId: string) {
  const account = await callApi('fetchLedgerAccount', accountId);
  if (!account!.byChain.ton) {
    throw new Error(`Ton wallet missing in account ${accountId}`);
  }

  const path = getLedgerAccountPathByWallet(parseAccountId(accountId).network, account!.byChain.ton);

  await tonTransport!.validateAddress(path, {
    bounceable: IS_BOUNCEABLE,
    walletVersion: getInternalWalletVersion(account!.byChain.ton.version as PossibleWalletVersion),
  });
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

export function getTransport(): Transport | undefined {
  return transport;
}
