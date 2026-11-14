import type { ApiInitArgs, OnApiUpdate } from '../../types';
import type { MethodArgsWithMaybePrefix, MethodResponseWithMaybePrefix } from '../../types/methods';
import { type AllMethods, recognizeDappMethod } from '../../types/methods';

import { throttle } from '../../../util/schedulers';
import { isUpdaterAlive } from '../../common/helpers';
import { getProtocolManager } from '../../dappProtocols';
import { syncAndroidWalletAttribution } from '../../methods/attribution';
import init from '../../methods/init';
import { reportNativeInstallation } from '../../methods/nativeInstallation';
import { methods } from '../../methods/registry';
import { createStorage, withStorage } from '../../storages';

const INSTALLATION_RETRY_DELAY = 30000;

export function createDirectApiConnector() {
  let initPromise: Promise<void> | undefined;
  let requestReport = () => {};
  let requestWalletClaim = () => {};
  let stopReporting = () => {};
  let runtimeStorage = createStorage();

  function initApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs | (() => ApiInitArgs)) {
    stopReporting();
    const args = typeof initArgs === 'function' ? initArgs() : initArgs;

    const isAndroidInstallation = Boolean(args.isAndroidApp);
    const isNativeInstallation = isAndroidInstallation || Boolean(args.isIosApp);
    runtimeStorage = createStorage(args.storage);
    const targetStorage = runtimeStorage;
    const ready = withStorage(targetStorage, () => init(onUpdate, args));
    void ready.catch(() => {});
    initPromise = ready;
    const isAlive = () => initPromise === ready && isUpdaterAlive(onUpdate);
    let retryTimeout: ReturnType<typeof setTimeout> | undefined;
    let claimRetryTimeout: ReturnType<typeof setTimeout> | undefined;
    const report = throttle(async () => {
      clearTimeout(retryTimeout);
      if (!isAlive()) return;
      const isAcknowledged = await reportNativeInstallation(isAlive);
      if (!isAcknowledged && isAlive()) retryTimeout = setTimeout(report, INSTALLATION_RETRY_DELAY);
    }, () => Promise.resolve());
    const claim = throttle(async () => {
      clearTimeout(claimRetryTimeout);
      try {
        await ready;
        if (!isAlive()) return;
        const isClaimed = await syncAndroidWalletAttribution(targetStorage, isAlive);
        if (!isClaimed && isAlive()) claimRetryTimeout = setTimeout(claim, INSTALLATION_RETRY_DELAY);
      } catch { /* Wallet initialization failure must not stop installation delivery. */ }
    }, () => Promise.resolve());
    stopReporting = () => {
      clearTimeout(retryTimeout);
      clearTimeout(claimRetryTimeout);
    };
    requestReport = () => {
      if (isNativeInstallation && isAlive()) report();
    };
    requestWalletClaim = () => {
      if (isAndroidInstallation && isAlive()) claim();
    };
    requestReport();
    requestWalletClaim();
  }

  async function callApi<T extends keyof AllMethods>(
    fnName: T,
    ...args: MethodArgsWithMaybePrefix<T>
  ): Promise<MethodResponseWithMaybePrefix<T>> {
    await initPromise!;

    return withStorage(runtimeStorage, () => {
      const parsedRequest = recognizeDappMethod(fnName);

      if (parsedRequest.isDapp) {
        const adapter = getProtocolManager().getAdapter(parsedRequest.protocolType);
        if (!adapter) {
          throw new Error('No dApp adapter found for request');
        }
        const method = adapter[parsedRequest.fnName].bind(adapter);

        // @ts-ignore
        return method(...args);
      }
      // @ts-ignore
      return methods[fnName](...args) as MethodResponseWithMaybePrefix<T>;
    });
  }

  function handleInstallationStateChange() {
    requestReport();
    requestWalletClaim();
  }

  return {
    handleInstallationStateChange,
    initApi,
    callApi,
  };
}

const defaultConnector = createDirectApiConnector();

export const {
  initApi, callApi, handleInstallationStateChange,
} = defaultConnector;
