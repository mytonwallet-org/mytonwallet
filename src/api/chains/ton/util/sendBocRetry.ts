import { pause } from '../../../../util/schedulers';

type WaitForWalletSeqnoOptions = {
  getWalletSeqno: () => Promise<number | undefined>;
  seqno: number;
  waitMs: number;
  pauseMs: number;
};

export async function waitUntilWalletSeqnoChanges({
  getWalletSeqno,
  seqno,
  waitMs,
  pauseMs,
}: WaitForWalletSeqnoOptions) {
  const waitUntil = Date.now() + waitMs;

  while (Date.now() < waitUntil) {
    const walletSeqno = await getWalletSeqno().catch(() => undefined);
    if (isWalletSeqnoAdvanced(walletSeqno, seqno)) {
      return true;
    }

    await pause(pauseMs);
  }

  return false;
}

function isWalletSeqnoAdvanced(walletSeqno: number | undefined, seqno: number) {
  return walletSeqno !== undefined && walletSeqno > seqno;
}
