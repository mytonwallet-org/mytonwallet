import { APP_ENV, DEBUG_ALERT_MSG } from '../config';
import { SECOND } from './dateFormat';
import { IS_EXTENSION_PAGE_SCRIPT } from './environment';
import { logDebugError } from './logs';
import { throttle } from './schedulers';

const shouldShowAlert = (APP_ENV === 'development' || APP_ENV === 'staging')
  && typeof window === 'object'
  && !IS_EXTENSION_PAGE_SCRIPT;

const throttledAlert = throttle((message) => window.alert(message), 10 * SECOND);

self.addEventListener('error', handleErrorEvent);
self.addEventListener('unhandledrejection', handleErrorEvent);

function handleErrorEvent(e: ErrorEvent | PromiseRejectionEvent) {
  // https://stackoverflow.com/questions/49384120/resizeobserver-loop-limit-exceeded
  if (e instanceof ErrorEvent && e.message === 'ResizeObserver loop limit exceeded') {
    return;
  }

  e.preventDefault();

  handleError(e instanceof ErrorEvent ? (e.error || e.message) : e.reason);
}

export function handleError(err: Error | string) {
  logDebugError('handleError', err);

  const message = typeof err === 'string' ? err : err.message;
  const stack = typeof err === 'object' ? err.stack : undefined;

  if (message.endsWith('Failed to import rlottie-wasm.js')) {
    return;
  }

  if (APP_ENV === 'staging' && message === 'Failed to fetch') {
    return;
  }

  if (shouldShowAlert) {
    throttledAlert(`${DEBUG_ALERT_MSG}\n\n${(message) || err}\n${stack}`);
  }
}
