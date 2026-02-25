import type {
  Base58EncodedBytes } from '@solana/kit';
import {
  getBase58Decoder,
  getBase58Encoder,
  getBase64Decoder,
  getBase64Encoder,
  getTransactionDecoder,
  getTransactionEncoder,
} from '@solana/kit';
import nacl from 'tweetnacl';

import type { DappProtocolType, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiAnyDisplayError, ApiSignedTransfer } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';

export async function signPayload(
  accountId: string,
  payloadToSign: UnifiedSignDataPayload,
  password?: string,
): Promise<{ result: string } | { error: ApiAnyDisplayError }> {
  if (password === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = (await fetchPrivateKeyString(accountId, password))!;
  const signer = getSignerFromPrivateKey(network, privateKey);

  if (payloadToSign.type !== 'text') {
    return { error: ApiCommonError.Unexpected };
  }

  const messageBytes = new Uint8Array(getBase58Encoder().encode(payloadToSign.text));

  const signature = nacl.sign.detached(messageBytes, signer.secretKey);

  const isValid = nacl.sign.detached.verify(messageBytes, signature, signer.publicKeyBytes);

  if (!isValid) {
    return { error: ApiCommonError.InvalidPassword };
  }

  return { result: getBase58Decoder().decode(signature) };
}

export async function signTransfer(
  accountId: string,
  transaction: string,
  password?: string,
  isLegacyOutput?: boolean,
): Promise<ApiSignedTransfer<DappProtocolType.WalletConnect>[] | { error: ApiAnyDisplayError }> {
  if (password === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const txBytes = getBase64Encoder().encode(transaction);

  const decoder = getTransactionDecoder();
  const decodedTransaction = decoder.decode(txBytes);

  const privateKey = (await fetchPrivateKeyString(accountId, password))!;
  const signer = getSignerFromPrivateKey(network, privateKey);

  const mySignatureBytes = nacl.sign.detached(new Uint8Array(decodedTransaction.messageBytes), signer.secretKey);

  const signedTransaction = Object.freeze({
    ...decodedTransaction,
    signatures: Object.freeze({
      ...decodedTransaction.signatures,
      [signer.address]: mySignatureBytes,
    }),
  });

  const encoder = getTransactionEncoder();

  const signedBytes = encoder.encode(signedTransaction);

  const outputDecoder = isLegacyOutput ? getBase58Decoder() : getBase64Decoder();

  const base58Transaction = outputDecoder.decode(signedBytes) as Base58EncodedBytes;
  const base58Signature = outputDecoder.decode(mySignatureBytes);

  return [{
    chain: 'solana',
    payload: {
      signature: base58Signature,
      base58Tx: base58Transaction,
    },
  }];
}
