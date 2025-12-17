import type { TronWeb } from 'tronweb';

import type { ApiAddressInfo, ApiNetwork } from '../../types';
import { ApiCommonError } from '../../types';

import isEmptyObject from '../../../util/isEmptyObject';
import { logDebugError } from '../../../util/logs';
import { getTronClient } from './util/tronweb';
import { getKnownAddressInfo } from '../../common/addresses';
import { isValidAddress } from './address';

/*
* We display unconfirmed balance and transactions to user.
* /wallet/* - endpoints with unconfirmed data
* /walletsolidity/* - endpoints with confirmed data
*/

export async function getWalletBalance(network: ApiNetwork, address: string) {
  const tronWeb = getTronClient(network);
  return BigInt(await tronWeb.trx.getUnconfirmedBalance(address));
}

export async function getTrc20Balance(network: ApiNetwork, tokenAddress: string, address: string) {
  const result = await callContract(getTronClient(network), tokenAddress, 'balanceOf(address)', [
    { type: 'address', value: address },
  ], address);

  if (!result.length) {
    return 0n;
  }

  return BigInt(`0x${result[0]}`);
}

export async function callContract(
  tronWeb: TronWeb,
  address: string,
  functions: string,
  parameters: any[] = [],
  issuerAddress: string,
) {
  try {
    const result = await tronWeb.transactionBuilder.triggerSmartContract(
      address,
      functions,
      { _isConstant: true },
      parameters,
      issuerAddress,
    );
    return result && result.result ? result.constant_result : [];
  } catch (err: any) {
    logDebugError('callContract', err);
    return [];
  }
}

export async function isTronAccountMultisig(network: ApiNetwork, address: string) {
  try {
    const tronWeb = getTronClient(network);
    const account = await tronWeb.trx.getAccount(address);
    if (!account || isEmptyObject(account)) {
      return false;
    }
    const managerAddresses = new Set<string>();
    if (account.owner_permission.threshold > 1) {
      return true;
    }
    for (const permKey of account.owner_permission.keys) {
      managerAddresses.add(tronWeb.address.fromHex(permKey.address));
    }
    for (const perm of account.active_permission) {
      if (perm.threshold > 1) {
        return true;
      }
      for (const permKey of perm.keys) {
        managerAddresses.add(tronWeb.address.fromHex(permKey.address));
      }
    }

    if (managerAddresses.size > 1) {
      return true;
    }

    for (const managerAddress of managerAddresses) {
      if (managerAddress !== address) {
        return true;
      }
    }

    return false;
  } catch (e) {
    logDebugError('isTronAccountMultisig', e);
    return false;
  }
}

export function getAddressInfo(
  network: ApiNetwork,
  addressOrDomain: string,
): ApiAddressInfo | { error: ApiCommonError } {
  if (!isValidAddress(network, addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    resolvedAddress: addressOrDomain,
    addressName: getKnownAddressInfo(addressOrDomain)?.name,
  };
}
