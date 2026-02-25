/**
 * Dapp Protocol Manager
 *
 * Central coordination point for all dApp connection protocols.
 * Routes requests to appropriate adapters based on protocol type.
 */

import type { AppEnvironment } from '../environment';
import type { OnApiUpdate } from '../types';
import type { StoredDappConnection } from './storage';
import type {
  AbstractDappProtocolManager,
  DappProtocolAdapter,
  DappProtocolConfig,
  DappProtocolRegistration,
} from './types';
import {
  DappProtocolType,
} from './types';

import { logDebugError } from '../../util/logs';
import { chains } from '../chains';
import { getTonConnectAdapter, getWalletConnectAdapter } from './adapters';

class DappProtocolManager implements AbstractDappProtocolManager {
  public adapters = new Map<DappProtocolType, DappProtocolRegistration>();

  private config?: DappProtocolConfig;

  registerAdapter(adapter: DappProtocolAdapter): void {
    if (this.adapters.has(adapter.protocolType)) {
      logDebugError('DappProtocolManager', `Adapter for ${adapter.protocolType} already registered`);
      return;
    }

    this.adapters.set(adapter.protocolType, {
      adapter,
      initialized: false,
    });
  }

  async init(config: DappProtocolConfig): Promise<void> {
    this.config = config;

    const initPromises = Array.from(this.adapters.values()).map(async (registration) => {
      if (registration.initialized) return;

      try {
        await registration.adapter.init(config);
        registration.initialized = true;
      } catch (err) {
        logDebugError('DappProtocolManager', `Failed to init ${registration.adapter.protocolType}:`, err);
      }
    });

    await Promise.all(initPromises);
  }

  getAdapter(type: DappProtocolType): DappProtocolAdapter | undefined {
    return this.adapters.get(type)?.adapter;
  }

  async handleDeepLink(
    url: string,
    isFromInAppBrowser?: boolean,
    requestId?: string,
  ): Promise<string | undefined> {
    // Find the adapter that can handle this deep link
    for (const registration of this.adapters.values()) {
      if (!registration.initialized) continue;

      const { adapter } = registration;
      if (adapter.canHandleDeepLink(url)) {
        return adapter.handleDeepLink(url, isFromInAppBrowser, requestId);
      }
    }

    logDebugError('DappProtocolManager', `No adapter found for deep link: ${url}`);
    return undefined;
  }

  async resetupRemoteConnection(protocol?: DappProtocolType): Promise<void> {
    for (const registration of this.adapters.values()) {
      if (!registration.initialized) continue;

      const { adapter } = registration;
      if (protocol) {
        if (adapter.protocolType === protocol) {
          return adapter.resetupRemoteConnection?.();
        }
      } else {
        return adapter.resetupRemoteConnection?.();
      }
    }
  }

  async closeRemoteConnection(accountId: string, dapp: StoredDappConnection): Promise<void> {
    const adapter = this.getAdapter(dapp.protocolType ?? DappProtocolType.TonConnect)!;
    return adapter.closeRemoteConnection(accountId, dapp);
  }

  async destroy(): Promise<void> {
    const destroyPromises = Array.from(this.adapters.values())
      .filter((r) => r.initialized)
      .map(async (registration) => {
        try {
          await registration.adapter.destroy();
          registration.initialized = false;
        } catch (err) {
          logDebugError('DappProtocolManager', `Failed to destroy ${registration.adapter.protocolType}:`, err);
        }
      });

    await Promise.all(destroyPromises);
    this.adapters.clear();
  }
}

// Singleton instance
let protocolManager: DappProtocolManager | undefined;

export function getProtocolManager(): DappProtocolManager {
  if (!protocolManager) {
    protocolManager = new DappProtocolManager();
  }
  return protocolManager;
}

export function initProtocolManager(onUpdate: OnApiUpdate, env: AppEnvironment): Promise<void> {
  const manager = getProtocolManager();

  manager.registerAdapter(getTonConnectAdapter());
  manager.registerAdapter(getWalletConnectAdapter());

  const chainDappSupports = Object.fromEntries(
    (Object.entries(chains))
      .filter(([, sdk]) => !!sdk.dapp)
      .map(([chain, sdk]) => [chain, sdk.dapp]),
  );

  return manager.init({ onUpdate, env, chainDappSupports });
}

// Re-export types
export * from './types';
