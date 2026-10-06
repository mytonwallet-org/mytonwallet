import { withTimeout } from './schedulers';

const WINDOW_ID_REQUEST = 'getExtensionWindowId';
const RESPONSE_TIMEOUT = 500;
const RESPONSE_ATTEMPTS = 3;

export function initExtensionWindow() {
  navigator.serviceWorker?.addEventListener('message', ({ data, ports }) => {
    if (data !== WINDOW_ID_REQUEST || !ports[0]) return;

    const port = ports[0];
    self.chrome.windows.getCurrent((window) => {
      port.postMessage(self.chrome.runtime.lastError ? undefined : window.id);
      port.close();
    });
  });
}

export async function getExtensionWindowIds() {
  const popupUrl = self.chrome.runtime.getURL('index.html');

  if (self.chrome.runtime.getContexts) {
    const contexts = await self.chrome.runtime.getContexts({ documentUrls: [popupUrl], frameIds: [0] });
    return { windowIds: contexts.map(({ windowId }) => windowId), isComplete: true };
  }

  const { clients } = self as unknown as ServiceWorkerGlobalScope;
  if (!clients) return { windowIds: [], isComplete: true };

  const windowClients = await clients.matchAll({ type: 'window', includeUncontrolled: true });
  const ownClients = windowClients.filter(({ url, frameType }) => url === popupUrl && frameType === 'top-level');
  const results = await Promise.allSettled(ownClients.map(getClientWindowId));
  return {
    windowIds: results.flatMap((result) => (result.status === 'fulfilled' ? [result.value] : [])),
    isComplete: results.every((result) => result.status === 'fulfilled'),
  };
}

async function getClientWindowId(client: WindowClient) {
  for (let attempt = 0; attempt < RESPONSE_ATTEMPTS; attempt++) {
    const channel = new MessageChannel();
    try {
      const response = new Promise<unknown>((resolve) => {
        channel.port1.onmessage = ({ data }) => resolve(data);
        client.postMessage(WINDOW_ID_REQUEST, [channel.port2]);
      });
      const windowId = await withTimeout(response, RESPONSE_TIMEOUT, undefined);
      if (typeof windowId === 'number' && Number.isInteger(windowId) && windowId >= 0) {
        return windowId;
      }
    } finally {
      channel.port1.close();
      channel.port2.close();
    }
  }

  throw new Error('The extension window is not ready');
}
