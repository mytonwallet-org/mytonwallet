import type { ApiAnyDisplayError } from '../../types';

export async function getIsLedgerAppOpen(): Promise<boolean | { error: ApiAnyDisplayError }> {
  if (process.env.NO_LEDGER === '1') throw new Error('Ledger is disabled');

  const { isLedgerTonAppOpen } = await import('./ledger');
  return isLedgerTonAppOpen();
}
