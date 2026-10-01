import { APP_ENV, DEBUG_ALERT_MSG } from '../config';
import { isChunkLoadError } from './chunkLoading';
import { SECOND } from './dateFormat';
import { IS_EXTENSION_PAGE_SCRIPT } from './environment';
import { logDebugError } from './logs';
import { throttle } from './schedulers';

const shouldShowAlert = (APP_ENV === 'development' || APP_ENV === 'staging')
  && typeof window === 'object'
  && !IS_EXTENSION_PAGE_SCRIPT;

const throttledAlert = throttle((message) => window.alert(message), 10 * SECOND);
const errorEventTarget = typeof self === 'object' && typeof self.addEventListener === 'function' ? self : undefined;

errorEventTarget?.addEventListener('error', handleErrorEvent);
errorEventTarget?.addEventListener('unhandledrejection', handleErrorEvent);

function handleErrorEvent(e: ErrorEvent | PromiseRejectionEvent) {
  // https://stackoverflow.com/questions/49384120/resizeobserver-loop-limit-exceeded
  if (e instanceof ErrorEvent && isResizeObserverLoopError(e.message)) {
    return;
  }

  e.preventDefault();

  handleError(e instanceof ErrorEvent ? (e.error || e.message) : e.reason);
}

export function isResizeObserverLoopError(message: string) {
  return message === 'ResizeObserver loop limit exceeded'
    || message === 'ResizeObserver loop completed with undelivered notifications.';
}

export function handleError(err: Error | string) {
  logDebugError('handleError', err);

  const message = typeof err === 'string' ? err : err.message;
  const stack = typeof err === 'object' ? err.stack : undefined;

  if (APP_ENV === 'staging' && message.endsWith('Failed to fetch')) {
    return;
  }

  // The reload prompt covers a lazy chunk that failed to load, wherever its rejection went unhandled
  if (isChunkLoadError(err)) {
    return;
  }

  if (shouldShowAlert) {
    throttledAlert(`${DEBUG_ALERT_MSG}\n\n${(message) || err}\n${stack}`);
  }
}
