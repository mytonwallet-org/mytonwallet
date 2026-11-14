export enum StorageType {
  IndexedDb,
  LocalStorage,
  ExtensionLocal,
  AirStorage,
  NodeFile,
}

export interface NodeFileStorageConfig {
  type: 'nodeFile';
  path?: string;
  profile?: string;
}

export type ApiStorageConfig = NodeFileStorageConfig;

export interface Storage {
  getItem(name: StorageKey, force?: boolean): Promise<any>;

  setItem(name: StorageKey, value: any): Promise<void>;

  mutateItem?(name: StorageKey, mutate: (currentValue: any) => any): Promise<any>;

  removeItem(name: StorageKey): Promise<void>;

  clear(): Promise<void>;

  getAll?(): Promise<AnyLiteral>;

  setMany?(items: AnyLiteral): Promise<void>;

  getMany?(keys: string[]): Promise<AnyLiteral>;
}

export type StorageKey = 'layerzeroSwaps'
  | 'accounts'
  | 'stateVersion'
  | 'currentAccountId'
  | 'clientId'
  | 'webFirstLaunch'
  | 'webFunnelHandoff'
  | 'referrer'
  | 'langCode'
  | 'tonDnsCache'
  // For install attribution
  | 'attributionClaimed'
  | 'attributionChannel'
  | 'installAttribution'
  | 'installMetadata'
  | 'attributionTechnicalClaimed'
  | 'attributionOutcomeClaimed'
  // For extension
  | 'dapps'
  | 'dappMethods:lastAccountId'
  | 'windowId'
  | 'windowState'
  | 'isTonProxyEnabled'
  | 'isDeeplinkHookEnabled'
  | 'legacyCoreAccountsConverted'
  | 'legacyCoreMigrationCompleted'
  // For TonConnect SSE
  | 'sseLastEventId'
  | 'sseDelivery'
  // For Agent
  | 'agentMessages'
  | 'agentConversationId'
  | 'agentV2DeviceIdentity'
  | 'agentV2Consent'
  // For Headless
  | 'headlessBalanceSnapshots';
