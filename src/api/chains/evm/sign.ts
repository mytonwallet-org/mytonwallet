import { getBytes, Transaction } from 'ethers';

import type { DappProtocolType, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiAnyDisplayError, ApiNetwork, ApiSignedTransfer, EVMChain } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';

export type Eip712TypedDataFields = {
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  message: Record<string, unknown>;
};

export async function signEip712WithPrivateKey(
  network: ApiNetwork,
  privateKey: string,
  typedData: Eip712TypedDataFields,
): Promise<string> {
  const signer = getSignerFromPrivateKey(network, privateKey);
  const { domain, types, message } = typedData;
  const { EIP712Domain, ...typesForSigning } = types;

  return signer.signTypedData(domain, typesForSigning, message);
}

export async function signPayload(
  chain: EVMChain,
  accountId: string,
  payloadToSign: UnifiedSignDataPayload,
  enclaveToken?: string,
): Promise<{ result: string } | { error: ApiAnyDisplayError }> {
  if (enclaveToken === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  if (payloadToSign.type === 'eip712') {
    const signature = await signEip712WithPrivateKey(network, privateKey, payloadToSign);
    return { result: signature };
  }

  if (payloadToSign.type !== 'binary') {
    return { error: ApiCommonError.Unexpected };
  }

  const signer = getSignerFromPrivateKey(network, privateKey);

  // personal_sign passes the message as a hex-encoded byte string; decode it to raw bytes
  // so ethers applies the EIP-191 prefix to the original bytes, not to the hex literal.
  // eth_sign uses the same EIP-191 path (params: [address, data]).
  const messageBytes = payloadToSign.bytes.startsWith('0x')
    ? getBytes(payloadToSign.bytes)
    : payloadToSign.bytes;

  const signature = await signer.signMessage(messageBytes);
  return { result: signature };
}

export async function signTransfer(
  chain: EVMChain,
  accountId: string,
  transaction: string,
  enclaveToken?: string,
  isLegacyOutput?: boolean,
): Promise<ApiSignedTransfer<DappProtocolType.WalletConnect>[] | { error: ApiAnyDisplayError }> {
  if (enclaveToken === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  const signer = getSignerFromPrivateKey(network, privateKey);

  const txRequest = Transaction.from(transaction);

  const signedTx = await signer.signTransaction(txRequest);
  const signature = Transaction.from(signedTx).signature!.serialized;

  return [{
    chain,
    payload: {
      signature,
      signedTx: signedTx as any,
    },
  }];
}
