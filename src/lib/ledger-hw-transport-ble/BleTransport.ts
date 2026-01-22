/* eslint-disable @typescript-eslint/no-redundant-type-constituents */
import type { BleService } from '@capacitor-community/bluetooth-le';
import { BleClient, ConnectionPriority } from '@capacitor-community/bluetooth-le';
import type { BluetoothInfos, DeviceModel } from '@ledgerhq/devices';
import { DeviceModelId, getBluetoothServiceUuids, getInfosForServiceUuid } from '@ledgerhq/devices';
import { receiveAPDU } from '@ledgerhq/devices/lib/ble/receiveAPDU';
// ---------------------------------------------------------------------------------------------
// Since this is a react-native library and metro bundler does not support
// package exports yet (see: https://github.com/facebook/metro/issues/670)
// we need to import the file directly from the lib folder.
// Otherwise it would force the consumer of the lib to manually "tell" metro to resolve to /lib.
//
// TLDR: /!\ Do not remove the /lib part in the import statements below (@ledgerhq/devices/lib) ! /!\
// See: https://github.com/LedgerHQ/ledger-live/pull/879
import { sendAPDU } from '@ledgerhq/devices/lib/ble/sendAPDU';
import type { HwTransportError } from '@ledgerhq/errors';
import {
  CantOpenDevice,
  DisconnectedDeviceDuringOperation,
  PairingFailed,
  TransportError,
  TransportExchangeTimeoutError,
} from '@ledgerhq/errors';
import type { Observer as TransportObserver, Subscription as TransportSubscription } from '@ledgerhq/hw-transport';
import Transport from '@ledgerhq/hw-transport';
import type { TraceContext } from '@ledgerhq/logs';
import { LocalTracer, trace } from '@ledgerhq/logs';
import type { Observable, SchedulerLike } from 'rxjs';
import {
  defer, firstValueFrom, from, merge, of, throwError, TimeoutError,
} from 'rxjs';
import {
  catchError, finalize, first, ignoreElements, map, share, tap, timeout,
} from 'rxjs/operators';
import { v4 as uuid } from 'uuid';
import type { BleCharacteristic } from '@capacitor-community/bluetooth-le/dist/esm/definitions';

import type { IOBleErrorRemap } from './remapErrors';
import type { Characteristic, Device, ReconnectionConfig } from './types';

import { awaitsBleOn } from './awaitsBleOn';
import { monitorCharacteristic } from './monitorCharacteristic';
import { decoratePromiseErrors, remapError } from './remapErrors';

const LOG_TYPE = 'ble-verbose';

const PAIRING_ERROR_MESSAGES = [
  'notify change failed',
  'encryption',
  'pairing',
  'notifications timeout', // When the user does not press the `Cancel` button for a long time
];

/**
 * This is potentially not needed anymore, to be checked if the bug is still happening.
 */
const reconnectionConfig: ReconnectionConfig | null | undefined = {
  pairingThreshold: 1000,
  delayAfterFirstPairing: 4000,
};

// Allows us to give more granulary error messages
const bluetoothInfoCache: Record<string, BluetoothInfos> = {};

function retrieveInfos(device: Device | null): BluetoothInfos | undefined {
  if (!device || !device.uuids) return undefined;
  const [serviceUUID] = device.uuids;
  if (!serviceUUID) return undefined;
  const infos = getInfosForServiceUuid(serviceUUID);
  if (!infos) return undefined;

  // If we retrieved information, update the cache
  bluetoothInfoCache[device.deviceId] = infos;
  return infos;
}

const delay = (ms: number | undefined) => new Promise((success) => setTimeout(success, ms));

/**
 * A cache of Bluetooth transport instances associated with device IDs.
 * Allows efficient storage and retrieval of previously initialized transports.
 * @type {Object.<string, BluetoothTransport>}
 */
const transportsCache: Record<string, BleTransport> = {};

// `connectOptions` is actually used by `react-native-ble-plx` even if comment above `ConnectionOptions` says it's not used
const connectOptions: Record<string, unknown> = {
  // 156 bytes to max the iOS < 10 limit (158 bytes)
  // (185 bytes for iOS >= 10)(up to 512 bytes for Android, but could be blocked at 23 bytes)
  requestMTU: 156,
  // Priority 1 = high.
  connectionPriority: 1,
};

const clearDisconnectTimeout = (deviceId: string, context?: TraceContext): void => {
  const cachedTransport = transportsCache[deviceId];
  if (cachedTransport && cachedTransport.disconnectTimeout) {
    trace({ type: LOG_TYPE, message: 'Clearing queued disconnect', context });
    clearTimeout(cachedTransport.disconnectTimeout);
  }
};

let currentDeviceService: string | undefined;

/**
 * React Native bluetooth BLE implementation
 * @example
 * import BleTransport from "@ledgerhq/react-native-hw-transport-ble";
 */
export default class BleTransport extends Transport {
  static disconnectTimeoutMs = 5000;

  static list = (): Promise<void[]> => {
    throw new Error('not implemented');
  };

  /**
   * Scan for bluetooth Ledger devices
   * @param observer Device is partial in order to avoid the live-common/this dep
   * @returns TransportSubscription
   */
  static listen(
    observer: TransportObserver<any, HwTransportError>,
  ): TransportSubscription {
    let unsubscribed: boolean = false;
    const tracer = new LocalTracer(LOG_TYPE);
    tracer.trace('Listening for devices ...');

    void BleClient.getConnectedDevices(getBluetoothServiceUuids()).then(async (devices) => {
      if (unsubscribed) return;
      for (const it of devices) {
        observer.next({
          type: 'add',
          device: it,
        });
      }
      await BleClient.stopLEScan();
      void BleClient.requestLEScan({
        services: getBluetoothServiceUuids(),
      }, (result) => {
        if (unsubscribed) return;
        observer.next({
          type: 'add',
          device: result.device,
        });
      });
    });

    return {
      unsubscribe: async () => {
        unsubscribed = true;
        await BleClient.stopLEScan();
      },
    };
  }

  /**
   * Opens a BLE transport
   *
   * @param {Device | string} deviceOrId
   * @param timeoutMs Applied when trying to connect to a device
   * @param context An optional context object for log/tracing strategy
   * @param injectedDependencies Contains optional injected dependencies used by the transport implementation
   *  - rxjsScheduler: dependency injected RxJS scheduler to control time. Default AsyncScheduler.
   */
  static async open(
    deviceOrId: Device | string,
    timeoutMs?: number,
    context?: TraceContext,
    { rxjsScheduler }: { rxjsScheduler?: SchedulerLike } = {},
  ): Promise<BleTransport> {
    return open(deviceOrId, true, timeoutMs, context, { rxjsScheduler });
  }

  /**
   * Exposes method from the ble-plx library to disconnect a device
   *
   * Disconnects from {@link Device} if it's connected or cancels pending connection.
   * A "disconnect" event will normally be emitted by the ble-plx lib once the device is disconnected.
   * Errors are logged but silenced.
   */
  static disconnectDevice = async (id: string,
    onDisconnect?: (e?: Error) => void,
    context?: TraceContext): Promise<void> => {
    const tracer = new LocalTracer(LOG_TYPE, context);
    tracer.trace(`Trying to disconnect device ${id}`);

    try {
      await BleClient.disconnect(id);
      onDisconnect?.();
    } catch (err: any) {
      // Only log, ignore if disconnect did not work
      tracer
        .withType('ble-error')
        .trace('Error while trying to cancel device connection', { error: err });
    }
    tracer.trace(`Device ${id} disconnected`);
  };

  device: Device;

  deviceModel: DeviceModel;

  // eslint-disable-next-line no-null/no-null
  disconnectTimeout: null | ReturnType<typeof setTimeout> = null;

  id: string;

  isConnected = true;

  mtuSize = 20;

  // Observable emitting data received from the device via BLE
  notifyObservable: Observable<Buffer | Error>;

  notYetDisconnected = true;

  writableWithResponseCharacteristic: Characteristic;

  writableWithoutResponseCharacteristic: Characteristic | undefined;

  rxjsScheduler?: SchedulerLike;

  // Transaction ids of communication operations that are currently pending
  currentTransactionIds: Array<string>;

  onDisconnect: ((error?: Error) => void) | undefined;

  disconnectCallback: (() => void) | undefined;

  /**
   * The static `open` function is used to handle `BleTransport` instantiation
   *
   * @param device
   * @param writableWithResponseCharacteristic A BLE characteristic that we can write on,
   *   and that will be acknowledged in response from the device when it receives the written value.
   * @param writableWithoutResponseCharacteristic A BLE characteristic that we can write on,
   *   and that will not be acknowledged in response from the device
   * @param notifyObservable A multicast observable that emits messages received from the device
   * @param deviceModel
   * @param params Contains optional options and injected dependencies used by the transport implementation
   *  - abortTimeoutMs: stop the exchange after a given timeout. Another timeout exists
   *    to detect unresponsive device (see `unresponsiveTimeout`). This timeout aborts the exchange.
   *  - rxjsScheduler: dependency injected RxJS scheduler to control time. Default: AsyncScheduler.
   */
  constructor(
    device: Device,
    writableWithResponseCharacteristic: Characteristic,
    writableWithoutResponseCharacteristic: Characteristic | undefined,
    notifyObservable: Observable<Buffer | Error>,
    deviceModel: DeviceModel,
    { context, rxjsScheduler }: { context?: TraceContext; rxjsScheduler?: SchedulerLike } = {},
  ) {
    super({ context, logType: LOG_TYPE });
    this.id = device.deviceId;
    this.device = device;
    this.writableWithResponseCharacteristic = writableWithResponseCharacteristic;
    this.writableWithoutResponseCharacteristic = writableWithoutResponseCharacteristic;
    this.notifyObservable = notifyObservable;
    this.deviceModel = deviceModel;
    this.rxjsScheduler = rxjsScheduler;
    this.currentTransactionIds = [];

    clearDisconnectTimeout(this.id);

    this.tracer.trace(`New instance of BleTransport for device ${this.id}`);
  }

  /**
   * A message exchange (APDU request <-> response) with the device that can be aborted.
   *
   * The message will be BLE-encoded/framed before being sent, and the response will be BLE-decoded.
   *
   * @param message A buffer (u8 array) of a none BLE-encoded message (an APDU for ex) to be sent to the device
   *   as a request
   * @param options Contains optional options for the exchange function
   *  - abortTimeoutMs: stop the exchange after a given timeout. Another timeout exists
   *    to detect unresponsive device (see `unresponsiveTimeout`). This timeout aborts the exchange.
   * @returns A promise that resolves with the response data from the device.
   */
  exchange = (
    message: Buffer,
    { abortTimeoutMs }: { abortTimeoutMs?: number } = {},
  ): Promise<Buffer> => {
    if (this.exchangeBusyPromise) {
      void BleTransport.disconnectDevice(this.id, this.onDisconnect);
    }
    const tracer = this.tracer.withUpdatedContext({
      function: 'exchange',
    });
    tracer.trace('Exchanging APDU ...', { abortTimeoutMs });
    tracer.withType('apdu').trace(`=> ${message.toString('hex')}`);

    return this.exchangeAtomicImpl(() => {
      return firstValueFrom(
        // `sendApdu` will only emit if an error occurred, otherwise it will complete,
        // while `receiveAPDU` will emit the full response.
        // Consequently, it monitors the response while being able to reject on an error from the send.
        merge(
          this.notifyObservable.pipe((data) => receiveAPDU(data, { context: tracer.getContext() })),
          sendAPDU(this.write, message, this.mtuSize, {
            context: tracer.getContext(),
          }),
        ).pipe(
          abortTimeoutMs ? timeout(abortTimeoutMs, this.rxjsScheduler) : tap(),
          tap((data) => {
            tracer.withType('apdu').trace(`<= ${data.toString('hex')}`);
          }),
          catchError(async (err: any) => {
            // Currently only 1 reason the exchange has been explicitly aborted (other than job and transport errors): a timeout
            if (err instanceof TimeoutError) {
              tracer.trace(
                'Aborting due to timeout and trying to cancel all communication write of the current exchange',
                {
                  abortTimeoutMs,
                  transactionIds: this.currentTransactionIds,
                },
              );

              // No concurrent exchange should happen at the same time, so all pending operations are part of the same exchange
              await this.cancelPendingOperations();

              throw new TransportExchangeTimeoutError('Exchange aborted due to timeout');
            }

            tracer.withType('ble-error').trace('Error while exchanging APDU', { error: err });

            if (this.notYetDisconnected) {
              // In such case we will always disconnect because something is bad.
              // This sends a `disconnect` event.
              await BleTransport.disconnectDevice(this.id, this.onDisconnect);
            }

            const mappedError = remapError(err as IOBleErrorRemap);
            tracer.trace('Error while exchanging APDU, mapped and throws following error', {
              mappedError,
            });
            // eslint-disable-next-line @typescript-eslint/only-throw-error
            throw mappedError;
          }),
          finalize(() => {
            tracer.trace('Clearing current transaction ids', {
              currentTransactionIds: this.currentTransactionIds,
            });
            this.clearCurrentTransactionIds();
          }),
        ),
      );
    });
  };

  private async cancelPendingOperations() {
    // BleTransport does not support cancellation
    await BleTransport.disconnectDevice(this.id, this.onDisconnect);
  }

  /**
   * Sets the collection of current transaction ids to an empty array
   */
  private clearCurrentTransactionIds() {
    this.currentTransactionIds = [];
  }

  /**
   * Negotiate with the device the maximum transfer unit for the ble frames
   * @returns Promise<number>
   */
  async inferMTU(): Promise<number> {
    let mtu = (await BleClient.getMtu(this.device.deviceId));
    this.tracer.trace('Inferring MTU ...', { currentDeviceMtu: mtu });

    await this.exchangeAtomicImpl(async () => {
      try {
        mtu = await firstValueFrom(
          merge(
            this.notifyObservable.pipe(
              map((maybeError) => {
                // Catches the `PairingFailed` Error that has only been emitted
                if (maybeError instanceof Error) {
                  throw maybeError;
                }

                return maybeError;
              }),
              first((buffer) => buffer.readUInt8(0) === 0x08),
              map((buffer) => buffer.readUInt8(5)),
            ),
            defer(() => from(this.write(Buffer.from([0x08, 0, 0, 0, 0])))).pipe(ignoreElements()),
          ),
        );
      } catch (err: any) {
        this.tracer.withType('ble-error').trace('Error while inferring MTU', { mtu, error: err });

        await BleTransport.disconnectDevice(this.id, this.onDisconnect);

        const mappedError = remapError(err);
        this.tracer.trace('Error while inferring APDU, mapped and throws following error', {
          mappedError,
        });
        // eslint-disable-next-line @typescript-eslint/only-throw-error
        throw mappedError;
      } finally {
        // When negotiating the MTU, a message is sent/written to the device, and a transaction id was associated to this write
        this.clearCurrentTransactionIds();
      }
    });

    this.tracer.trace('Successfully negotiated MTU with device', {
      mtu,
      mtuSize: this.mtuSize,
    });
    if (mtu > 20) {
      this.mtuSize = mtu;
    }

    return this.mtuSize;
  }

  /**
   * Exposed method from the ble-plx library.
   * Request the connection priority for the given device.
   * @returns {Promise<void>}
   * @param connectionPriority
   */
  async requestConnectionPriority(
    connectionPriority: 'Balanced' | 'High' | 'LowPower',
  ): Promise<void> {
    let connectionPriorityMapped: ConnectionPriority;
    switch (connectionPriority) {
      case 'High':
        connectionPriorityMapped = ConnectionPriority.CONNECTION_PRIORITY_BALANCED;
        break;
      case 'LowPower':
        connectionPriorityMapped = ConnectionPriority.CONNECTION_PRIORITY_LOW_POWER;
        break;
      case 'Balanced':
        connectionPriorityMapped = ConnectionPriority.CONNECTION_PRIORITY_BALANCED;
        break;
    }
    await decoratePromiseErrors(
      BleClient.requestConnectionPriority(this.device.deviceId, connectionPriorityMapped),
    );
  }

  /**
   * Do not call this directly unless you know what you're doing. Communication
   * with a Ledger device should be through the {@link exchange} method.
   *
   * For each call a transaction id is added to the current stack of transaction ids.
   * With this transaction id, a pending BLE communication operations can be cancelled.
   * Note: each frame/packet of a longer BLE-encoded message to be sent should have their unique transaction id.
   *
   * @param buffer BLE-encoded packet to send to the device
   * @param frameId Frame id to make `write` aware of a bigger message that this frame/packet is part of.
   *  Helps to create related a collection of transaction ids
   */
  write = async (buffer: Buffer): Promise<void> => {
    const transactionId = uuid();
    this.currentTransactionIds.push(transactionId);

    const tracer = this.tracer.withUpdatedContext({ transactionId });
    tracer.trace('Writing to device', {
      willMessageBeAcked: !this.writableWithoutResponseCharacteristic,
    });

    try {
      const uint8Array = new Uint8Array(buffer);
      const dataView = new DataView(uint8Array.buffer, uint8Array.byteOffset, uint8Array.byteLength);
      await BleClient.write(
        this.device.deviceId,
        currentDeviceService!,
        this.writableWithResponseCharacteristic.uuid,
        dataView,
      );
      tracer.withType('ble-frame').trace(`=> ${buffer.toString('hex')}`);
    } catch (err: any) {
      tracer.trace('Error while writing APDU', { error: err });
      throw new DisconnectedDeviceDuringOperation(
        err instanceof Error ? err.message : `${String(err)}`,
      );
    }
  };

  /**
   * We intentionally do not immediately close a transport connection.
   * Instead, we queue the disconnect and wait for a future connection to dismiss the event.
   * This approach prevents unnecessary disconnects and reconnects. We use the isConnected
   * flag to ensure that we do not trigger a disconnect if the current cached transport has
   * already been disconnected.
   * @returns {Promise<void>}
   */
  async close(): Promise<void> {
    const tracer = this.tracer.withUpdatedContext({ function: 'close' });
    tracer.trace('Closing, queuing a disconnect with a timeout ...');

    let resolve: (value: void | PromiseLike<void>) => void;
    const disconnectPromise = new Promise<void>((innerResolve) => {
      resolve = innerResolve;
    });

    clearDisconnectTimeout(this.id);

    this.disconnectTimeout = setTimeout(() => {
      tracer.trace('Disconnect timeout has been reached ...');
      if (this.isConnected) {
        BleTransport.disconnectDevice(this.id, this.onDisconnect, tracer.getContext())
          .catch(() => {})
          .finally(resolve);
      } else {
        resolve();
      }
    }, BleTransport.disconnectTimeoutMs);

    // The closure will occur no later than 5s, triggered either by disconnection
    // or the actual response of the apdu.
    await Promise.race([this.exchangeBusyPromise || Promise.resolve(), disconnectPromise]);
  }
}

/**
 * Opens a BLE connection with a given device. Returns a Transport instance.
 *
 * @param deviceOrId
 * @param needsReconnect
 * @param timeoutMs Optional Timeout (in ms) applied during the connection with the device
 * @param context Optional tracing/log context
 * @param injectedDependencies Contains optional injected dependencies used by the transport implementation
 *  - rxjsScheduler: dependency injected RxJS scheduler to control time. Default AsyncScheduler.
 * @returns A BleTransport instance
 */
async function open(
  deviceOrId: Device | string,
  needsReconnect: boolean,
  timeoutMs?: number,
  context?: TraceContext,
  { rxjsScheduler }: { rxjsScheduler?: SchedulerLike } = {},
) {
  const tracer = new LocalTracer(LOG_TYPE, context);
  let device: Device;
  tracer.trace(`Opening ${typeof deviceOrId === 'string' ? deviceOrId : deviceOrId.deviceId}`, { needsReconnect });
  let deviceId: string;
  // eslint-disable-next-line prefer-const
  let transport: BleTransport;

  if (typeof deviceOrId === 'string') {
    deviceId = deviceOrId;
    if (transportsCache[deviceOrId]) {
      tracer.trace('Transport in cache, using it');
      clearDisconnectTimeout(deviceOrId);

      // The cached transport probably has an older trace/log context
      transportsCache[deviceOrId].setTraceContext(context);
      return transportsCache[deviceOrId];
    }

    tracer.trace(`Trying to open device: ${deviceOrId}`);
    await awaitsBleOn();

    // Returns a list of known devices by their identifiers
    const devices = (await BleClient.getDevices([deviceOrId]));
    tracer.trace(`Found ${devices.length} already known device(s) with given id`, { deviceOrId });
    [device] = devices;

    if (!device) {
      // Returns a list of the peripherals currently connected to the system
      // which have discovered services, connected to system doesn't mean
      // connected to our app, we check that below.
      const services = (await BleClient.getServices(deviceOrId)).map((it) => it.uuid);
      const connectedDevices = (await BleClient.getConnectedDevices(services));
      const connectedDevicesFiltered = connectedDevices.filter((d) => d.deviceId === deviceOrId);
      tracer.trace(
        `No known device with given id.
        Found ${connectedDevicesFiltered.length} devices from already connected devices`,
        { deviceOrId },
      );
      [device] = connectedDevicesFiltered;
    }

    if (!device) {
      // We still don't have a device, so we attempt to connect to it.
      tracer.trace('No known nor connected devices with given id. Trying to connect to device', {
        deviceOrId,
        timeoutMs,
      });

      // Nb ConnectionOptions dropped since it's not used internally by ble-plx.
      try {
        await BleClient.connect(deviceOrId, () => {
          transport.onDisconnect?.();
        }, {
          timeout: timeoutMs,
        });
      } catch (e: any) {
        tracer.trace(`Error code: ${e.errorCode}`);
        throw e;
      }
    }

    if (!device) {
      throw new CantOpenDevice();
    }
  } else {
    // It was already a Device
    device = deviceOrId;
    deviceId = deviceOrId.deviceId;
  }

  const connectedDevices = await BleClient.getConnectedDevices(getBluetoothServiceUuids());

  if (!connectedDevices.find((it) => it.deviceId === deviceId)) {
    tracer.trace('Device found but not connected. connecting...', { timeoutMs, connectOptions });
    try {
      await BleClient.connect(deviceId, () => {
        transport.onDisconnect?.();
      }, {
        timeout: timeoutMs,
      });
    } catch (err: any) {
      tracer.trace('Connect error', { error: err });
      // eslint-disable-next-line @typescript-eslint/only-throw-error
      throw remapError(err);
    }
  }

  tracer.trace('Device is connected now, getting services and characteristics');

  let services: BleService[] = [];

  await BleClient.discoverServices(deviceId);
  services = (await BleClient.getServices(deviceId));

  let res: BluetoothInfos | undefined = retrieveInfos(device);
  const characteristics: BleCharacteristic[] = [];

  if (!res) {
    for (const serviceUUID of getBluetoothServiceUuids()) {
      try {
        const deviceService = services.find((it) => it.uuid === serviceUUID);
        res = getInfosForServiceUuid(serviceUUID);
        if (res && deviceService) {
          characteristics.push(...deviceService.characteristics);
          currentDeviceService = res.serviceUuid;
          break;
        }
      } catch (e) {
        // Attempt to connect to the next service
      }
    }
  }

  if (!res) {
    tracer.trace('Service not found');
    throw new TransportError('service not found', 'BLEServiceNotFound');
  }

  const {
    deviceModel, writeUuid, writeCmdUuid, notifyUuid,
  } = res;

  /* if (!characteristics) {
    characteristics = await device.characteristicsForService(serviceUuid);
  } */

  if (!characteristics) {
    tracer.trace('Characteristics not found');
    throw new TransportError('service not found', 'BLEServiceNotFound');
  }

  let writableWithResponseCharacteristic: Characteristic | null | undefined;
  let writableWithoutResponseCharacteristic: Characteristic | undefined;
  // A characteristic that can monitor value changes
  let notifiableCharacteristic: Characteristic | null | undefined;

  for (const c of characteristics) {
    if (c.uuid === writeUuid) {
      writableWithResponseCharacteristic = c;
    } else if (c.uuid === writeCmdUuid) {
      writableWithoutResponseCharacteristic = c;
    } else if (c.uuid === notifyUuid) {
      notifiableCharacteristic = c;
    }
  }

  if (!writableWithResponseCharacteristic) {
    throw new TransportError('write characteristic not found', 'BLECharacteristicNotFound');
  }

  if (!notifiableCharacteristic) {
    throw new TransportError('notify characteristic not found', 'BLECharacteristicNotFound');
  }

  if (!writableWithResponseCharacteristic.properties.write) {
    throw new TransportError(
      'The writable-with-response characteristic is not writable with response',
      'BLECharacteristicInvalid',
    );
  }

  if (!notifiableCharacteristic.properties.notify) {
    throw new TransportError('notify characteristic not notifiable', 'BLECharacteristicInvalid');
  }

  if (writableWithoutResponseCharacteristic) {
    if (!writableWithoutResponseCharacteristic.properties.writeWithoutResponse) {
      throw new TransportError(
        'The writable-without-response characteristic is not writable without response',
        'BLECharacteristicInvalid',
      );
    }
  }

  const deviceMtu = await BleClient.getMtu(device.deviceId);
  tracer.trace(`device.mtu=${deviceMtu}`);

  // Inits the observable that will emit received data from the device via BLE
  const notifyObservable = monitorCharacteristic(deviceId,
    currentDeviceService!,
    notifiableCharacteristic,
    context).pipe(
    catchError((err: any) => {
      // LL-9033 fw 2.0.2 introduced this case, we silence the inner unhandled error.
      // It will be handled when negotiating the MTU in `inferMTU` but will be ignored in other cases.
      // Also handle "Encryption is insufficient" error when user cancels pairing dialog.
      const message = (err.message || String(err)).toLowerCase();
      const isPairingError = PAIRING_ERROR_MESSAGES.some((msg) => message.includes(msg));

      return isPairingError
        ? of(new PairingFailed(message))
        : throwError(() => err);
    }),
    tap((value) => {
      if (value instanceof PairingFailed) return;
      trace({ type: 'ble-frame', message: `<= ${value.toString('hex')}`, context });
    }),
    // Returns a new Observable that multicasts (shares) the original Observable.
    // As long as there is at least one Subscriber this Observable will be subscribed and emitting data.
    share(),
  );

  // Keeps the input from the device observable alive (multicast observable)
  const notif = notifyObservable.subscribe();

  transport = new BleTransport(
    device,
    writableWithResponseCharacteristic,
    writableWithoutResponseCharacteristic,
    notifyObservable,
    deviceModel,
    {
      context,
      rxjsScheduler,
    },
  );
  tracer.trace('New BleTransport created');

  // Keeping it as a comment for now but if no new bluetooth issues occur, we will be able to remove it
  // await transport.requestConnectionPriority("High");

  // let disconnectedSub: Subscription;

  // Callbacks on `react-native-ble-plx` notifying the device has been disconnected
  transport.onDisconnect = (error?: Error) => {
    transport.isConnected = false;
    transport.notYetDisconnected = false;
    notif.unsubscribe();
    // disconnectedSub?.remove();

    clearDisconnectTimeout(transport.id);
    delete transportsCache[transport.id];
    tracer.trace(
      `On device disconnected callback: cleared cached transport for ${transport.id},
      emitting Transport event "disconnect. Error: ${error}"`,
      { reason: error },
    );
    transport.emit('disconnect', error);
    transport.disconnectCallback?.();
  };

  transportsCache[transport.id] = transport;
  const beforeMTUTime = Date.now();

  /* disconnectedSub = device.onDisconnected((e) => {
    if (!transport.notYetDisconnected) return;
    onDisconnect(e);
  }); */

  try {
    await transport.inferMTU();
  } catch (err: any) {
    tracer.withType('ble-error').trace('Error during inferMTU in open, cleaning up', { error: err });

    // Clean up resources on error
    notif.unsubscribe();
    delete transportsCache[transport.id];

    try {
      await BleTransport.disconnectDevice(transport.id, transport.onDisconnect);
    } catch (disconnectError) {
      tracer.withType('ble-error').trace('Error while disconnecting after inferMTU failure', { disconnectError });
    }

    throw err;
  }

  const afterMTUTime = Date.now();

  if (reconnectionConfig) {
    // Refer to ledgerjs archived repo issue #279.
    // All HW .v1 LNX have a bug that prevents us from communicating with the device right after pairing.
    // When we connect for the first time we issue a disconnect and reconnect, this guarantees that we are
    // in a good state. This is avoidable in some key scenarios ↓
    if (afterMTUTime - beforeMTUTime < reconnectionConfig.pairingThreshold) {
      needsReconnect = false;
    } else if (deviceModel.id === DeviceModelId.stax) {
      tracer.trace('Skipping "needsReconnect" strategy for Stax');
      needsReconnect = false;
    }

    if (needsReconnect) {
      tracer.trace('Device needs reconnection. Triggering a disconnect');
      await BleTransport.disconnectDevice(transport.id, transport.onDisconnect);
      await delay(reconnectionConfig.delayAfterFirstPairing);
    }
  } else {
    needsReconnect = false;
  }

  if (needsReconnect) {
    tracer.trace('Reconnecting');
    return open(device, false, timeoutMs, context);
  }

  return transport;
}
