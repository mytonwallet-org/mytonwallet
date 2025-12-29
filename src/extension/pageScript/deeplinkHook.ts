import {
  SELF_PROTOCOL,
  SELF_UNIVERSAL_URLS,
  TON_PROTOCOL,
  TONCONNECT_PROTOCOL,
  TONCONNECT_PROTOCOL_SELF,
  TONCONNECT_UNIVERSAL_URL,
} from '../../util/deeplink/constants';
import { callApi } from '../../api/providers/extension/connectorForPageScript';

const originalOpenFn = window.open;
let isDeeplinkHookEnabled: boolean | undefined;

// Avoid handling `click` and `window.open` at the same time
let justHandledUrl: string | undefined;

const JUST_HANDLED_TIMEOUT = 100;

export function doDeeplinkHook(isTurnedOn: boolean) {
  if (isTurnedOn === Boolean(isDeeplinkHookEnabled)) {
    return;
  }

  if (isTurnedOn) {
    window.addEventListener('click', clickHandler, false);
    window.open = patchedOpenFn;
  } else {
    window.removeEventListener('click', clickHandler);
    window.open = originalOpenFn;
  }

  isDeeplinkHookEnabled = isTurnedOn;
}

function clickHandler(e: MouseEvent) {
  const linkEl = (e.target as HTMLElement)?.closest('a');
  const href = linkEl?.href;

  if (href && href !== justHandledUrl && isDeeplink(href)) {
    e.preventDefault();

    void callApi('processDeeplink', { url: href });

    justHandledUrl = linkEl.href;
    setTimeout(() => {
      justHandledUrl = undefined;
    }, JUST_HANDLED_TIMEOUT);
  }
}

function patchedOpenFn(url?: string | URL, ...args: any[]) {
  if (url && url !== justHandledUrl && isDeeplink(String(url))) {
    void callApi('processDeeplink', { url });

    justHandledUrl = url.toString();
    setTimeout(() => {
      justHandledUrl = undefined;
    }, JUST_HANDLED_TIMEOUT);

    // eslint-disable-next-line no-null/no-null
    return null;
  }

  return originalOpenFn(url, ...args);
}

function isDeeplink(url: string) {
  url = url.replace(/^http:\/\//, 'https://');

  return (
    url.startsWith(TON_PROTOCOL)
    || url.startsWith(SELF_PROTOCOL)
    || url.startsWith(TONCONNECT_PROTOCOL)
    || url.startsWith(TONCONNECT_PROTOCOL_SELF)
    || SELF_UNIVERSAL_URLS.some((universalUrl) => url.startsWith(universalUrl))
    || url.startsWith(TONCONNECT_UNIVERSAL_URL)
  );
}
