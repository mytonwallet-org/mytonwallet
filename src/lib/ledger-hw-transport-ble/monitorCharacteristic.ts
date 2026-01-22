import { BleClient } from '@capacitor-community/bluetooth-le';
import type { TraceContext } from '@ledgerhq/logs';
import { LocalTracer } from '@ledgerhq/logs';
import { Observable } from 'rxjs';

import type { Characteristic } from './types';

const LOG_TYPE = 'ble-verbose';

export const monitorCharacteristic = (
  deviceId: string,
  serviceId: string,
  characteristic: Characteristic,
  context?: TraceContext,
): Observable<Buffer> => new Observable((o) => {
  const tracer = new LocalTracer(LOG_TYPE, context);
  tracer.trace('Start monitoring BLE characteristics', {
    characteristicUuid: characteristic.uuid,
  });

  BleClient.startNotifications(
    deviceId,
    serviceId,
    characteristic.uuid,
    (value) => {
      const uint8Array = new Uint8Array(value.buffer);
      const buffer = Buffer.from(uint8Array);
      o.next(buffer);
    },
  ).catch((error) => {
    tracer.trace('Error starting BLE notifications', { error });
    o.error(error);
  });

  return () => {
    void BleClient.stopEnabledNotifications();
  };
});
