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

export type StorageKey = 'accounts'
  | 'stateVersion'
  | 'currentAccountId'
  | 'clientId'
  | 'referrer'
  | 'langCode'
  // For install attribution
  | 'attributionClaimed'
  | 'attributionChannel'
  | 'installAttribution'
  | 'attributionTechnicalClaimed'
  // For extension
  | 'dapps'
  | 'dappMethods:lastAccountId'
  | 'windowId'
  | 'windowState'
  | 'isTonProxyEnabled'
  | 'isDeeplinkHookEnabled'
  // For TonConnect SSE
  | 'sseLastEventId'
  // For Agent
  | 'agentMessages'
  | 'agentConversationId'
  | 'agentV2DeviceIdentity'
  | 'agentV2Consent'
  | 'agentV2WalletProtocolVersion'
  // For Headless
  | 'headlessBalanceSnapshots'
  // SDK activity reconciliation
  | 'walletOperationIntents'
  | 'activeCexSwapReconciliationState'
  | 'knownTonAggregatorTraceIds'
  | 'knownTonAggregatorTraceProjections';
