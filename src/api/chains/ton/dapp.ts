import { Address, Cell } from '@ton/core';

import type { DappProtocolType, DappSignDataResult, UnifiedSignDataPayload } from '../../dappProtocols';
import type { TonConnectProof } from '../../dappProtocols/adapters';
import type { ApiDappTransfer } from '../../types';
import type { TonTransferParams } from './types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { getSigner } from './util/signer';
import { toRawAddress } from './util/tonCore';
import { fetchStoredChainAccount } from '../../common/accounts';
import { fetchStoredWallet } from '../../common/accounts';
import { createMfaRequest } from '../../common/mfa';
import { getTokenBySlug } from '../../common/tokens';
import { bytesToHex } from '../../common/utils';
import { getStoredBackendAuthToken } from '../../methods/other';
import { signTransfers } from './transfer';

const mfaRefillQuotes = new Map<string, { amount: bigint }>();

function getMfaRefillQuoteKey(accountId: string, messages: ApiDappTransfer[]) {
  return JSON.stringify([accountId, messages.map((message) => [
    Address.parse(message.toAddress).toRawString(), message.amount.toString(),
    message.rawPayload ?? '', message.stateInit ?? '',
  ])]);
}

/** Keeps the SDK-prepared quote alive only while its TonConnect confirmation is pending. */
export function registerMfaRefillQuote(accountId: string, messages: ApiDappTransfer[], amount: bigint) {
  const key = getMfaRefillQuoteKey(accountId, messages);
  const quote = { amount };
  mfaRefillQuotes.set(key, quote);
  return () => {
    if (mfaRefillQuotes.get(key) === quote) mfaRefillQuotes.delete(key);
  };
}

export async function signConnectionProof(accountId: string, proof: TonConnectProof, enclaveToken?: string) {
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, enclaveToken);
  const signature = await signer.signTonProof(proof);
  if ('error' in signature) return signature;
  const publicKey = await signer.getSigningPublicKey();
  if ('error' in publicKey) return publicKey;

  return { signature: signature.toString('base64'), publicKey: bytesToHex(publicKey) };
}

export async function signDappTransfers(
  accountId: string,
  messages: ApiDappTransfer[],
  options: {
    enclaveToken?: string;
    vestingAddress?: string;
    /** Unix seconds */
    validUntil?: number;
  } = {}) {
  const { enclaveToken, validUntil, vestingAddress } = options;

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

  const account = await fetchStoredChainAccount(accountId, 'ton');
  let expectedMfaRefill: bigint | undefined;
  if (account.byChain.ton.mfa) {
    // TonConnect confirmation carries the complete SDK-prepared list, with its refill last.
    const quote = mfaRefillQuotes.get(getMfaRefillQuoteKey(accountId, messages));
    const refill = preparedMessages.pop();
    if (!quote || !refill || refill.amount !== quote.amount || refill.amount <= 0n || refill.payload || refill.stateInit
      || !Address.parse(refill.toAddress).equals(Address.parse(account.byChain.ton.mfa.address))) {
      return { error: ApiTransactionError.ConcurrentTransaction };
    }
    expectedMfaRefill = refill.amount;
  }

  const result = await signTransfers(
    accountId,
    preparedMessages,
    enclaveToken,
    validUntil,
    vestingAddress,
    true,
    expectedMfaRefill,
  );

  if (result && typeof result === 'object' && 'mfaRequest' in result) {
    const { address } = await fetchStoredWallet(accountId, 'ton');
    const { payload, signature, mfaRefillAmount } = result.mfaRequest;
    const authToken = await getStoredBackendAuthToken(accountId);

    const { reqId } = await createMfaRequest({
      walletAddress: address,
      payload: payload.toBoc(),
      signature,
      mfaRefillAmount: authToken ? mfaRefillAmount : undefined,
      authToken,
    });

    return { mfaRequestHash: reqId };
  }

  return result;
}

/**
 * See https://docs.tonconsole.com/academy/sign-data for more details
 */
export async function signDappData(
  accountId: string,
  dappUrl: string,
  payloadToSign: UnifiedSignDataPayload,
  enclaveToken?: string,
) {
  if (payloadToSign.type === 'eip712') {
    return { error: ApiCommonError.Unexpected };
  }

  const timestamp = Math.floor(Date.now() / 1000);
  const domain = new URL(dappUrl).host;

  const account = await fetchStoredChainAccount(accountId, 'ton');
  const signer = getSigner(accountId, account, enclaveToken);
  const signature = await signer.signData(timestamp, domain, payloadToSign);
  if ('error' in signature) return signature;

  const result: DappSignDataResult<DappProtocolType.TonConnect> = {
    chain: 'ton',
    result: {
      signature: signature.toString('base64'),
      address: toRawAddress(account.byChain.ton.address),
      timestamp,
      domain,
      payload: payloadToSign,
    },
  };
  return result;
}
