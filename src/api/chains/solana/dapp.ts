import type { DappProtocolType, DappSignDataResult, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiDappTransfer } from '../../types';

import { fetchStoredChainAccount } from '../../common/accounts';
import { signPayload, signTransfer } from './sign';

export async function signDappData(
  accountId: string,
  dappUrl: string,
  payloadToSign: UnifiedSignDataPayload,
  password?: string,
) {
  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, 'solana');
  const signature = await signPayload(accountId, payloadToSign, password);
  if ('error' in signature) return signature;

  const result: DappSignDataResult<DappProtocolType.WalletConnect> = {
    chain: 'solana',
    result: {
      signature: signature.result,
      address: account.byChain.solana.address,
      timestamp,
      domain,
      payload: payloadToSign,
    },
  };
  return result;
}

export async function signDappTransfers(
  accountId: string,
  messages: ApiDappTransfer[],
  options: {
    password?: string;
    vestingAddress?: string;
    /** Unix seconds */
    validUntil?: number;
    // Deal with solana b58/b64 issues based on requested method
    isLegacyOutput?: boolean;
  } = {}) {
  const { password, isLegacyOutput } = options;

  return signTransfer(
    accountId,
    messages[0].rawPayload!,
    password,
    isLegacyOutput,
  );
}
