import { getBytes, Transaction } from 'ethers';

import type { DappProtocolType, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiAnyDisplayError, ApiSignedTransfer, EVMChain } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';

export async function signPayload(
  chain: EVMChain,
  accountId: string,
  payloadToSign: UnifiedSignDataPayload,
  password?: string,
): Promise<{ result: string } | { error: ApiAnyDisplayError }> {
  if (password === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(chain, accountId, password);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  const signer = getSignerFromPrivateKey(network, privateKey);

  if (payloadToSign.type === 'eip712') {
    const { domain, types, message } = payloadToSign;
    const { EIP712Domain, ...typesForSigning } = types;
    void EIP712Domain;
    const signature = await signer.signTypedData(domain, typesForSigning, message);
    return { result: signature };
  }

  if (payloadToSign.type !== 'binary') {
    return { error: ApiCommonError.Unexpected };
  }

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
  password?: string,
  isLegacyOutput?: boolean,
): Promise<ApiSignedTransfer<DappProtocolType.WalletConnect>[] | { error: ApiAnyDisplayError }> {
  if (password === undefined) return { error: ApiCommonError.InvalidPassword };

  const { network } = parseAccountId(accountId);

  const privateKey = await fetchPrivateKeyString(chain, accountId, password);
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
