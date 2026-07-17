import type { ApiChain } from './misc';

export type NativePlatform = 'ios' | 'android';

export interface ApiNotificationAddress {
  title?: string;
  address: string;
  chain: ApiChain;
}

export interface ApiNotificationsAccountValue {
  key: string;
}

export interface ApiSubscribeNotificationsProps {
  userToken: string;
  platform: NativePlatform;
  langCode: string;
  addresses: ApiNotificationAddress[];
}

export interface ApiUnsubscribeNotificationsProps {
  userToken: string;
  addresses: ApiNotificationAddress[];
}

export interface ApiSubscribeNotificationsResult {
  ok: true;
  addressKeys: Record<string, ApiNotificationsAccountValue>;
}
