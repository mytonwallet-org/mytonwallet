import type { TonConnectProof } from '../../../dappProtocols/adapters';
import type { ApiNetwork, ApiTonWallet } from '../../../types';
import { ApiHardwareError } from '../../../types';

import { doesLedgerDeviceMatch, getLedgerAccountPathByWallet, handleLedgerTonError, tonTransport } from './utils';

export async function signTonProofWithLedger(
  network: ApiNetwork,
  wallet: ApiTonWallet,
  proof: TonConnectProof,
): Promise<Buffer | { error: ApiHardwareError }> {
  const accountPath = getLedgerAccountPathByWallet(network, wallet);
  const { timestamp, domain, payload } = proof;

  try {
    if (!await doesLedgerDeviceMatch(network, wallet)) {
      return { error: ApiHardwareError.WrongDevice };
    }

    const result = await tonTransport.getAddressProof(accountPath, {
      domain,
      timestamp,
      payload: Buffer.from(payload),
    });
    return result.signature;
  } catch (err) {
    return handleLedgerTonError(err);
  }
}
