import type { Base58EncodedBytes } from '@solana/kit';
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
import type { ApiAnyDisplayError, ApiNetwork, ApiSignedTransfer } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';

export async function signPayload(
  accountId: string,
  payloadToSign: UnifiedSignDataPayload,
  enclaveToken?: string,
): Promise<{ result: string } | { error: ApiAnyDisplayError }> {
  if (enclaveToken === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  const signer = getSignerFromPrivateKey(network, privateKey);

  if (payloadToSign.type !== 'binary') {
    return { error: ApiCommonError.Unexpected };
  }

  const messageBytes = new Uint8Array(getBase58Encoder().encode(payloadToSign.bytes));

  const signature = nacl.sign.detached(messageBytes, signer.secretKey);

  const isValid = nacl.sign.detached.verify(messageBytes, signature, signer.publicKeyBytes);

  if (!isValid) {
    return { error: ApiCommonError.InvalidPassword };
  }

  return { result: getBase58Decoder().decode(signature) };
}

export function partiallySignTransaction(
  network: ApiNetwork,
  privateKey: string,
  transaction: string,
): { signedBytes: Uint8Array; signatureBytes: Uint8Array } {
  const txBytes = getBase64Encoder().encode(transaction);

  const decoder = getTransactionDecoder();
  const decodedTransaction = decoder.decode(txBytes);

  const signer = getSignerFromPrivateKey(network, privateKey);

  const signatureBytes = nacl.sign.detached(new Uint8Array(decodedTransaction.messageBytes), signer.secretKey);

  const signedTransaction = Object.freeze({
    ...decodedTransaction,
    signatures: Object.freeze({
      ...decodedTransaction.signatures,
      [signer.address]: signatureBytes,
    }),
  });

  const encoder = getTransactionEncoder();

  const signedBytes = encoder.encode(signedTransaction);

  return { signedBytes: new Uint8Array(signedBytes), signatureBytes };
}

export async function signTransfers(
  accountId: string,
  transactions: string[],
  enclaveToken?: string,
  isLegacyOutput?: boolean,
): Promise<ApiSignedTransfer<DappProtocolType.WalletConnect>[] | { error: ApiAnyDisplayError }> {
  if (enclaveToken === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  return transactions.flatMap((transaction) =>
    signTransferWithPrivateKey(network, privateKey, transaction, isLegacyOutput),
  );
}

export function signTransfer(accountId: string, transaction: string, enclaveToken?: string, isLegacyOutput?: boolean) {
  return signTransfers(accountId, [transaction], enclaveToken, isLegacyOutput);
}

function signTransferWithPrivateKey(
  network: ApiNetwork,
  privateKey: string,
  transaction: string,
  isLegacyOutput?: boolean,
): ApiSignedTransfer<DappProtocolType.WalletConnect>[] {
  const { signedBytes, signatureBytes } = partiallySignTransaction(network, privateKey, transaction);

  const outputDecoder = isLegacyOutput ? getBase58Decoder() : getBase64Decoder();

  const serializedTransaction = outputDecoder.decode(signedBytes) as Base58EncodedBytes;
  const serializedSignature = outputDecoder.decode(signatureBytes);

  return [{
    chain: 'solana',
    payload: {
      signature: serializedSignature,
      signedTx: serializedTransaction,
    },
  }];
}
