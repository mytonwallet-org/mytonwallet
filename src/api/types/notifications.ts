import type { ApiChain } from './misc';

export type NativePlatform = 'ios' | 'android';

export type ApiNewsNotificationsMode = 'off' | 'digest' | 'news';

export interface ApiSetNewsNotificationsProps {
  mode: ApiNewsNotificationsMode;
  userToken: string;
  platform: NativePlatform;
  langCode: string;
  // Integer from 0 to 23, used for `digest`
  digestHour: number;
  // 0, 15, 30 or 45, used for `digest`
  digestMinute: number;
  // IANA time zone, used for `digest`
  timeZone: string;
}

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
