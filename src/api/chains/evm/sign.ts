import { Transaction } from 'ethers';

import type { DappProtocolType, UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiAnyDisplayError, ApiNetwork, ApiSignedTransfer, EVMChain } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { getPersonalSignBytes, isSmartAccountAuthorization } from './smartAccount/signingDomain';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { isTransactionOnChain } from './transactionChainId';
import { isTypedDataDomainOnChain } from './typedDataChainId';
import { isValidTypedDataDomain } from './typedDataDomain';
import { getSignedTypedDataDomain, getSignedTypedDataMessage } from './typedDataMessage';

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

  // A domain key outside EIP-712, `__proto__` for one, changes what ethers hashes but not what the checks below read
  if (payloadToSign.type === 'eip712' && payloadToSign.domain && !isValidTypedDataDomain(payloadToSign.domain)) {
    return { error: ApiCommonError.Unexpected };
  }

  // The confirmation shows `chain`, so typed data bound to another chain's domain is never signed here
  if (
    payloadToSign.type === 'eip712'
    && (
      (network === 'testnet' && payloadToSign.network === 'mainnet')
      || !isTypedDataDomainOnChain(payloadToSign.domain, payloadToSign.network ?? network, chain)
      || !getSignedTypedDataDomain(payloadToSign.domain)
      || !getSignedTypedDataMessage(payloadToSign.types, payloadToSign.primaryType, payloadToSign.message)
    )
  ) {
    return { error: ApiCommonError.Unexpected };
  }

  const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  const signer = getSignerFromPrivateKey(network, privateKey);

  // The same key authorizes the account as an EIP-7702 smart account, so a dApp never gets that signature
  if (isSmartAccountAuthorization(payloadToSign, signer.address)) {
    return { error: ApiCommonError.Unexpected };
  }

  if (payloadToSign.type === 'eip712') {
    const signature = await signEip712WithPrivateKey(network, privateKey, payloadToSign);
    return { result: signature };
  }

  if (payloadToSign.type !== 'binary') {
    return { error: ApiCommonError.Unexpected };
  }

  // personal_sign passes the message as a hex-encoded byte string; decode it to raw bytes
  // so ethers applies the EIP-191 prefix to the original bytes, not to the hex literal.
  // eth_sign uses the same EIP-191 path (params: [address, data]).
  const signature = await signer.signMessage(getPersonalSignBytes(payloadToSign.bytes));
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

  const txRequest = Transaction.from(transaction);

  // The confirmation shows `chain`, so a transaction for another chain id, or for none, is never signed here
  if (!isTransactionOnChain(txRequest, network, chain)) {
    return { error: ApiCommonError.Unexpected };
  }

  const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken);
  if (!privateKey) return { error: ApiCommonError.InvalidPassword };

  const signer = getSignerFromPrivateKey(network, privateKey);

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
