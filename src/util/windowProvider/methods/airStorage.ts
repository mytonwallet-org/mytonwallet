import type { StorageKey } from '../../../api/storages/types';
import type { InstallAttributionCandidate } from '../../installAttribution';

// These functions declare the window-side method contract for the native Air secure-storage bridge.
// In the Air app the calls are routed through `airAppCallWindow` and served natively; in web, extension
// and Electron the secure storage path is never taken (idb is the default storage). The bodies are
// therefore unreachable and exist only to define the bridge signatures.

function notAvailable(): Promise<never> {
  return Promise.reject(new Error('Air secure storage is not available in this build'));
}

export function airStorageGetItem(_key: StorageKey): Promise<string | undefined> {
  return notAvailable();
}

export function airStorageSetItem(_key: StorageKey, _value: string): Promise<{ value: boolean }> {
  return notAvailable();
}

export function airStorageRemoveItem(_key: StorageKey): Promise<{ value: boolean }> {
  return notAvailable();
}

export function airStorageClear(): Promise<{ value: boolean }> {
  return notAvailable();
}

export type AirInstallationSlot = 'play' | 'deeplink' | 'app_transaction';

type InstallationSource = {
  channel: string;
  attributionKind: 'utm' | 'referrer' | 'direct' | 'referral';
  sourceOutcome: string;
  referrerDomain?: string;
  utmMedium?: string;
  utmCampaign?: string;
  utmContent?: string;
};

export type InstallationEventV2 = {
  schemaVersion: 2;
  installationId: string;
  eventId: string;
  packageInstalledAt: number | null;
} & ({
  sourceTransport: 'play_referrer';
  collectionStatus: string;
  playInstalledAt: number | null;
  installVersion: string;
  source: InstallationSource | null;
} | {
  sourceTransport: 'deeplink';
  source: InstallationSource;
} | {
  sourceTransport: 'app_transaction';
  collectionStatus: string;
  originalPurchasedAt: number | null;
  storeEnvironment: string;
});

export interface AirInstallationPendingDelivery {
  slot: AirInstallationSlot;
  body: InstallationEventV2;
}

export function airInstallationGetPending(): Promise<AirInstallationPendingDelivery[]> {
  return notAvailable();
}

export function airInstallationAcknowledge(_slot: AirInstallationSlot, _acknowledgementJson: string): Promise<boolean> {
  return notAvailable();
}

export type AirWalletAttributionSource = InstallAttributionCandidate & { legacy?: true };

export function airInstallationSyncWalletAttribution(_legacySourceJson: string): Promise<{
  source: AirWalletAttributionSource | null;
  technicalKind: 'direct' | 'referral' | null;
  sourceOutcome?: string | null;
  playInstalledAt?: number | null;
  installationId?: string;
}> {
  return notAvailable();
}
