import { CONTENT_SCRIPT_PORT, PAGE_CONNECTOR_CHANNEL } from './config';
import { isPortDisconnectedError } from '../../../util/isPortDisconnectedError';

const PAGE_ORIGIN = window.location.href;

let port: chrome.runtime.Port;

window.addEventListener('message', handlePageMessage);

connectPort();

function handlePageMessage(e: MessageEvent) {
  if (e.data?.channel === PAGE_CONNECTOR_CHANNEL) {
    sendToPort(e.data);
  }
}

function connectPort() {
  port = chrome.runtime.connect({ name: CONTENT_SCRIPT_PORT });
  port.onMessage.addListener(sendToPage);
}

function sendToPage(payload: any) {
  window.postMessage(payload, PAGE_ORIGIN);
}

function sendToPort(payload: any, isRepeated = false) {
  try {
    port.postMessage(payload);
  } catch (err: any) {
    const isInvalidated = err.message.toString().includes('Extension context invalidated');
    if (isInvalidated) {
      window.removeEventListener('message', handlePageMessage);
      return;
    }

    const isDisconnected = isPortDisconnectedError(err);
    if (isDisconnected && !isRepeated) {
      connectPort();
      sendToPort(payload, true);
    }
  }
}
