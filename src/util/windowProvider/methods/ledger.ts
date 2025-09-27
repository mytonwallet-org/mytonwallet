import type { ApiLedgerDeviceModel } from '../../../api/types';

import { pick } from '../../iteratees';

// String is used instead of Buffer, because Buffer can't be transferred to/from worker.
// Uint8Array is not used because it can't be transferred to/from extension service worker.
export async function exchangeWithLedger(apduBase64: string): Promise<string> {
  const transport = await getTransport();
  const apduBuffer = Buffer.from(apduBase64, 'base64');
  const response = await transport.exchange(apduBuffer);
  return response.toString('base64');
}

export async function getLedgerDeviceModel(): Promise<ApiLedgerDeviceModel> {
  const { deviceModel } = await getTransport();
  return deviceModel && pick(deviceModel, ['id', 'productName']);
}

async function getTransport() {
  const { getTransportOrFail } = await import('../../ledger');
  return getTransportOrFail();
}
