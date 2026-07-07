import * as dappPromises from '../common/dappPromises';
import { DappProtocolType, getProtocolManager } from '../dappProtocols';

export function confirmWalletConnectPaySignTransaction(promiseId: string, data: unknown) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function confirmWalletConnectPaySignData(promiseId: string, data: unknown) {
  dappPromises.resolveDappPromise(promiseId, data);
}

export function completeWalletConnectPayDataCollection(promiseId: string) {
  dappPromises.resolveDappPromise(promiseId);
}

export function confirmWalletConnectPayOptionSelection(promiseId: string, optionId: string) {
  dappPromises.resolveDappPromise(promiseId, optionId);
}

export function cancelWalletConnectPay(promiseId: string, reason?: string) {
  dappPromises.rejectDappPromise(promiseId, reason);
}

export async function refreshWalletConnectPayOptionSelection(
  paymentLink: string,
  accountId: string,
  promiseId: string,
) {
  const adapter = getProtocolManager().getAdapter(DappProtocolType.WalletConnect);

  await adapter?.refreshPayOptionSelection?.(paymentLink, accountId, promiseId);
}
