import type { DappProtocolType, DappSignDataResult, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiDappTransfer } from '../../types';

import { fetchStoredChainAccount } from '../../common/accounts';
import { signPayload, signTransfers } from './sign';

export async function signDappData(
  accountId: string,
  dappUrl: string,
  payloadToSign: UnifiedSignDataPayload,
  enclaveToken?: string,
) {
  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, 'solana');
  const signature = await signPayload(accountId, payloadToSign, enclaveToken);

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
    enclaveToken?: string;
    vestingAddress?: string;
    // Unix seconds
    validUntil?: number;
    // Deal with solana b58/b64 issues based on requested method
    isLegacyOutput?: boolean;
  } = {}) {
  const { enclaveToken, isLegacyOutput } = options;

  return signTransfers(accountId, messages.map((message) => message.rawPayload!), enclaveToken, isLegacyOutput);
}
