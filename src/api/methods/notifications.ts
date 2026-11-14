import type {
  ApiSetNewsNotificationsProps, ApiSubscribeNotificationsProps, ApiSubscribeNotificationsResult,
  ApiUnsubscribeNotificationsProps,
} from '../types';

import { logDebugError } from '../../util/logs';
import { callBackendPost } from '../common/backend';
import { handleServerError } from '../errors';

export async function subscribeNotifications(props: ApiSubscribeNotificationsProps) {
  try {
    return await callBackendPost<ApiSubscribeNotificationsResult>(
      '/notifications/subscribe', props, { shouldRetry: true },
    );
  } catch (err) {
    logDebugError('subscribeNotifications', err);
    return handleServerError(err);
  }
}

export async function unsubscribeNotifications(props: ApiUnsubscribeNotificationsProps) {
  try {
    return await callBackendPost<{ ok: true }>(
      '/notifications/unsubscribe', props, { shouldRetry: true },
    );
  } catch (err) {
    logDebugError('unsubscribeNotifications', err);
    return handleServerError(err);
  }
}

export async function setNewsNotifications(
  props: ApiSetNewsNotificationsProps,
): Promise<{ ok: true } | ReturnType<typeof handleServerError>> {
  const {
    mode, userToken, platform, langCode, digestHour, digestMinute, timeZone,
  } = props;

  try {
    switch (mode) {
      case 'off':
        await callBackendPost<{ ok: true }>(
          '/notifications/news-digest/unsubscribe', { userToken }, { shouldRetry: true },
        );
        return await callBackendPost<{ ok: true }>(
          '/notifications/news/unsubscribe', { userToken }, { shouldRetry: true },
        );
      case 'digest':
        await callBackendPost<{ ok: true }>(
          '/notifications/news-digest/subscribe',
          {
            userToken, platform, hour: digestHour, minute: digestMinute, timezone: timeZone, langCode,
          },
          { shouldRetry: true },
        );
        return await callBackendPost<{ ok: true }>(
          '/notifications/news/unsubscribe', { userToken }, { shouldRetry: true },
        );
      case 'news':
        await callBackendPost<{ ok: true }>(
          '/notifications/news/subscribe', { userToken, platform, langCode }, { shouldRetry: true },
        );
        return await callBackendPost<{ ok: true }>(
          '/notifications/news-digest/unsubscribe', { userToken }, { shouldRetry: true },
        );
    }
  } catch (err) {
    logDebugError('setNewsNotifications', err);
    return handleServerError(err);
  }
}
