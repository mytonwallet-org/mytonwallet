import type { InstallationEventV2 } from '../../util/windowProvider/methods/airStorage';

import { BRILLIANT_API_BASE_URL } from '../../config';
import { mergeAbortSignalsWithTimeout, raceWithAbortSignal, throwIfAborted } from '../../util/abortSignal';
import { getBackendHeaders } from './backend';

const DELIVERY_TIMEOUT = 30000;

export async function postInstallationEvent(body: InstallationEventV2): Promise<unknown> {
  const headers: Record<string, string> = { ...getBackendHeaders(), 'Content-Type': 'application/json' };
  delete headers['X-App-ClientID'];
  const controller = new AbortController();
  const { signal, cleanup } = mergeAbortSignalsWithTimeout(DELIVERY_TIMEOUT, controller.signal);
  try {
    return await raceWithAbortSignal(async () => {
      const response = await fetch(new URL(`${BRILLIANT_API_BASE_URL}/attribution/install`).toString(), {
        method: 'POST',
        headers,
        body: JSON.stringify(body),
        signal,
      });
      throwIfAborted(signal);
      if (response.status !== 200) throw new Error(`Installation delivery failed: HTTP ${response.status}`);
      return response.json();
    }, signal);
  } finally {
    controller.abort();
    cleanup();
  }
}
