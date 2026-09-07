import type { InstallAttributionCandidate } from '../../../util/installAttribution';
import type { ApiInitArgs, OnApiUpdate } from '../../types';
import type { MethodArgsWithMaybePrefix, MethodResponseWithMaybePrefix } from '../../types/methods';
import { type AllMethods, recognizeDappMethod } from '../../types/methods';

import { normalizeAttributionCandidate } from '../../../util/installAttribution';
import { getProtocolManager } from '../../dappProtocols';
import { acceptInstallAttribution, setInstallChannel as claimLegacyInstallChannel } from '../../methods/attribution';
import init from '../../methods/init';
import { methods } from '../../methods/registry';
import { createStorage, withStorage } from '../../storages';

export function createDirectApiConnector() {
  let initPromise: Promise<void> | undefined;
  let attributionDrain: Promise<void> | undefined;
  const pendingAttribution: (
    { snapshot: InstallAttributionCandidate }
    | { channel: string; referrerDomain?: string; technicalKind?: 'referral' }
  )[] = [];
  let runtimeStorage = createStorage();

  function initApi(onUpdate: OnApiUpdate, initArgs: ApiInitArgs | (() => ApiInitArgs)) {
    const args = typeof initArgs === 'function' ? initArgs() : initArgs;

    runtimeStorage = createStorage(args.storage);
    initPromise = withStorage(runtimeStorage, () => init(onUpdate, args));
    flushAttribution();
  }

  function flushAttribution() {
    if (!initPromise || attributionDrain === initPromise) return;
    const ready = initPromise;
    attributionDrain = ready;
    const targetStorage = runtimeStorage;
    let initialized = false;
    let failed = false;
    void ready.then(async () => {
      initialized = true;
      while (pendingAttribution.length && initPromise === ready) {
        const pending = pendingAttribution[0];
        if ('snapshot' in pending) {
          await acceptInstallAttribution(pending.snapshot, targetStorage);
        } else {
          await claimLegacyInstallChannel(
            pending.channel, targetStorage, pending.referrerDomain, pending.technicalKind,
          );
        }
        if (pendingAttribution[0] === pending) pendingAttribution.shift();
      }
    }).catch(() => { failed = true; }).finally(() => {
      if (attributionDrain === ready) attributionDrain = undefined;
      if (pendingAttribution.length && ((initialized && !failed) || initPromise !== ready)) flushAttribution();
    });
  }

  function captureInstallAttribution(snapshot: InstallAttributionCandidate) {
    const candidate = normalizeAttributionCandidate(snapshot);
    if (!candidate) return;
    pendingAttribution.push({ snapshot: candidate });
    flushAttribution();
  }

  function setInstallChannel(channel: string, referrerDomain?: string, technicalKind?: 'referral') {
    if (technicalKind === 'referral' || (!referrerDomain && ['organic', 'unknown'].includes(channel))) {
      pendingAttribution.push({ channel, referrerDomain, technicalKind });
      flushAttribution();
      return;
    }
    captureInstallAttribution({ channel, attributionKind: referrerDomain ? 'referrer' : 'utm', referrerDomain });
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

  return {
    initApi,
    callApi,
    setInstallChannel,
    captureInstallAttribution,
  };
}

const defaultConnector = createDirectApiConnector();

export const { initApi, callApi, setInstallChannel, captureInstallAttribution } = defaultConnector;
