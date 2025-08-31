// String is used instead of Buffer, because Buffer can't be transferred to/from worker.
// Uint8Array is not used because it can't be transferred to/from extension service worker.
export async function exchangeWithLedger(apduBase64: string): Promise<string> {
  const { getTransport } = await import('../../ledger');
  const transport = getTransport();
  if (!transport) {
    throw new Error('Ledger transport is not initialized');
  }

  const apduBuffer = Buffer.from(apduBase64, 'base64');
  const response = await transport.exchange(apduBuffer);
  return response.toString('base64');
}
