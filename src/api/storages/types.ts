export enum StorageType {
  IndexedDb,
  LocalStorage,
  ExtensionLocal,
  CapacitorStorage,
}

export interface Storage {
  getItem(name: StorageKey, force?: boolean): Promise<any>;

  setItem(name: StorageKey, value: any): Promise<void>;

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
  // For extension
  | 'dapps'
  | 'dappMethods:lastAccountId'
  | 'windowId'
  | 'windowState'
  | 'isTonProxyEnabled'
  | 'isDeeplinkHookEnabled'
  // For TonConnect SSE
  | 'sseLastEventId';
