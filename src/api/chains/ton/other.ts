import type { ApiAnyDisplayError } from '../../types';

export async function getIsLedgerAppOpen(): Promise<boolean | { error: ApiAnyDisplayError }> {
  const { isLedgerTonAppOpen } = await import('./ledger');
  return isLedgerTonAppOpen();
}
