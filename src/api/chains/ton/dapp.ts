import { Cell } from '@ton/core';

import type { DappProtocolType, DappSignDataResult, UnifiedSignDataPayload } from '../../dappProtocols';
import type { TonConnectProof } from '../../dappProtocols/adapters';
import type { ApiDappTransfer } from '../../types';
import type { TonTransferParams } from './types';

import { getSigner } from './util/signer';
import { fetchStoredChainAccount } from '../../common/accounts';
import { getTokenBySlug } from '../../common/tokens';
import { signTransfers } from './transfer';

export async function signConnectionProof(accountId: string, proof: TonConnectProof, password?: string) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, password);
  const signature = await signer.signTonProof(proof);
  if ('error' in signature) return signature;

  return { signature: signature.toString('base64') };
}

export async function signDappTransfers(
  accountId: string,
  messages: ApiDappTransfer[],
  options: {
    password?: string;
    vestingAddress?: string;
    /** Unix seconds */
    validUntil?: number;
  } = {}) {
  const { password, validUntil, vestingAddress } = options;

  const preparedMessages = messages.map(({
    toAddress,
    amount,
    stateInit: stateInitBase64,
    rawPayload,
    payload,
  }): TonTransferParams => ({
    toAddress,
    amount,
    payload: rawPayload ? Cell.fromBase64(rawPayload) : undefined,
    stateInit: stateInitBase64 ? Cell.fromBase64(stateInitBase64) : undefined,
    hints: {
      tokenAddress: payload?.type === 'tokens:transfer'
        ? getTokenBySlug(payload.slug)?.tokenAddress
        : undefined,
    },
  }));

  return signTransfers(
    accountId,
    preparedMessages,
    password,
    validUntil,
    vestingAddress,
    true,
  );
}

/**
 * See https://docs.tonconsole.com/academy/sign-data for more details
 */
export async function signDappData(
  accountId: string,
  dappUrl: string,
  payloadToSign: UnifiedSignDataPayload,
  password?: string,
) {
  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, password);
  const signature = await signer.signData(timestamp, domain, payloadToSign);
  if ('error' in signature) return signature;

  const result: DappSignDataResult<DappProtocolType.TonConnect> = {
    chain: 'ton',
    result: {
      signature: signature.toString('base64'),
      address: account.byChain.ton.address,
      timestamp,
      domain,
      payload: payloadToSign,
    },
  };
  return result;
}
