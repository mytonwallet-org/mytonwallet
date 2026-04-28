import type { DappProtocolType, DappSignDataResult, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiDappTransfer, EVMChain } from '../../types';

import { fetchStoredChainAccount } from '../../common/accounts';
import { signPayload, signTransfer } from './sign';

export async function signDappData(
  chain: EVMChain,
  accountId: string,
  dappUrl: string,
  payloadToSign: UnifiedSignDataPayload,
  password?: string,
) {
  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, chain);

  const signature = await signPayload(chain, accountId, payloadToSign, password);

  if ('error' in signature) return signature;

  const result: DappSignDataResult<DappProtocolType.WalletConnect> = {
    chain,
    result: {
      signature: signature.result,
      address: account.byChain[chain].address,
      timestamp,
      domain,
      payload: payloadToSign,
    },
  };
  return result;
}

export async function signDappTransfers(
  chain: EVMChain,
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

  return await signTransfer(
    chain,
    accountId,
    messages[0].rawPayload!,
    password,
    isLegacyOutput,
  );
}
