import { Cell } from '@ton/core';
import type { SignDataPayload, SignDataRpcResponseSuccess } from '@tonconnect/protocol';

import type { TonTransferParams } from '../chains/ton/types';
import type { ApiTonConnectProof } from '../tonConnect/types';
import type { ApiTransferToSign } from '../types';

import * as ton from '../chains/ton';
import { getSigner } from '../chains/ton/util/signer';
import { fetchStoredChainAccount } from '../common/accounts';
import { getTokenBySlug } from '../common/tokens';

export { startSseConnection } from '../tonConnect/sse';

export async function signTonProof(accountId: string, proof: ApiTonConnectProof, password?: string) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, password);
  const signature = await signer.signTonProof(proof);
  if ('error' in signature) return signature;

  return { signature: signature.toString('base64') };
}

export async function signTransfers(accountId: string, messages: ApiTransferToSign[], options: {
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

  return ton.signTransfers(
    accountId,
    preparedMessages,
    password,
    validUntil,
    vestingAddress,
  );
}

/**
 * See https://docs.tonconsole.com/academy/sign-data for more details
 */
export async function signData(accountId: string, dappUrl: string, payloadToSign: SignDataPayload, password?: string) {
  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, password);
  const signature = await signer.signData(timestamp, domain, payloadToSign);
  if ('error' in signature) return signature;

  const result: SignDataRpcResponseSuccess['result'] = {
    signature: signature.toString('base64'),
    address: account.byChain.ton.address,
    timestamp,
    domain,
    payload: payloadToSign,
  };
  return result;
}
