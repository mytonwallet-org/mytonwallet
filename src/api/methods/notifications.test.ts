import type { ApiNewsNotificationsMode } from '../types';
import type { MethodArgs } from './types';
import { ApiCommonError } from '../types';

import Deferred from '../../util/Deferred';
import { logDebugError } from '../../util/logs';
import { callBackendPost } from '../common/backend';
import { ApiServerError } from '../errors';
import { setNewsNotifications } from './notifications';

jest.mock('../common/backend', () => ({ callBackendPost: jest.fn() }));
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));

const PROPS: MethodArgs<'setNewsNotifications'>[0] = {
  mode: 'digest',
  userToken: 'device-push-token',
  platform: 'ios',
  langCode: 'ru',
  digestHour: 9,
  digestMinute: 45,
  timeZone: 'Europe/Moscow',
};
const EXPECTED_REQUESTS = {
  off: [
    ['/notifications/news-digest/unsubscribe', { userToken: 'device-push-token' }, { shouldRetry: true }],
    ['/notifications/news/unsubscribe', { userToken: 'device-push-token' }, { shouldRetry: true }],
  ],
  digest: [
    ['/notifications/news-digest/subscribe', {
      userToken: 'device-push-token', platform: 'ios', hour: 9, minute: 45, timezone: 'Europe/Moscow', langCode: 'ru',
    }, { shouldRetry: true }],
    ['/notifications/news/unsubscribe', { userToken: 'device-push-token' }, { shouldRetry: true }],
  ],
  news: [
    ['/notifications/news/subscribe', {
      userToken: 'device-push-token', platform: 'ios', langCode: 'ru',
    }, { shouldRetry: true }],
    ['/notifications/news-digest/unsubscribe', { userToken: 'device-push-token' }, { shouldRetry: true }],
  ],
};

describe('setNewsNotifications', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.mocked(callBackendPost).mockReset().mockResolvedValue({ ok: true });
  });

  it.each<ApiNewsNotificationsMode>(['off', 'digest', 'news'])(
    'sets %s with sequential requests and the exact backend bodies',
    async (mode) => {
      const firstRequest = new Deferred<{ ok: true }>();
      jest.mocked(callBackendPost).mockReturnValueOnce(firstRequest.promise);

      const result = setNewsNotifications({ ...PROPS, mode });
      await Promise.resolve();
      expect(callBackendPost).toHaveBeenCalledTimes(1);

      firstRequest.resolve({ ok: true });
      await expect(result).resolves.toEqual({ ok: true });
      expect(jest.mocked(callBackendPost).mock.calls).toEqual(EXPECTED_REQUESTS[mode]);
    },
  );

  it.each<ApiNewsNotificationsMode>(['digest', 'news'])(
    'returns a failed %s subscription without unsubscribing',
    async (mode) => {
      const error = new ApiServerError('Subscription failed', 503);
      jest.mocked(callBackendPost).mockRejectedValueOnce(error);

      await expect(setNewsNotifications({ ...PROPS, mode })).resolves.toEqual({ error: ApiCommonError.ServerError });

      expect(jest.mocked(callBackendPost).mock.calls).toEqual([EXPECTED_REQUESTS[mode][0]]);
      expect(logDebugError).toHaveBeenCalledWith('setNewsNotifications', error);
    },
  );

  it('returns an unsubscribe failure after a successful subscription', async () => {
    const error = new ApiServerError('Unsubscription failed', 503);
    jest.mocked(callBackendPost).mockResolvedValueOnce({ ok: true }).mockRejectedValueOnce(error);

    await expect(setNewsNotifications(PROPS)).resolves.toEqual({ error: ApiCommonError.ServerError });

    expect(jest.mocked(callBackendPost).mock.calls).toEqual(EXPECTED_REQUESTS.digest);
    expect(logDebugError).toHaveBeenCalledWith('setNewsNotifications', error);
  });
});
