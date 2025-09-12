import type { DeviceModelId } from '@ledgerhq/devices';

// This type has only several fields from DeviceModel, because the Air apps implement only that fields.
export type ApiLedgerDeviceModel = null | undefined | {
  id: DeviceModelId;
  productName: string;
};
