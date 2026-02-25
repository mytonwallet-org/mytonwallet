import type { CapacitorPlatform } from '../../util/capacitor/platform';
import type { ApiChain } from './misc';

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
  platform: CapacitorPlatform;
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
