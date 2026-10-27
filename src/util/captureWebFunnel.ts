import type { WebFunnelContext } from './webFunnel';

import { GLOBAL_STATE_CACHE_KEY, IS_AIR_APP, IS_EXPLORER, IS_EXTENSION, IS_TELEGRAM_APP } from '../config';
import { mutateWebFunnelStorage } from '../api/storages/webFunnel';
import { getWebFunnelVisitId, isWebFunnelOrigin, WEB_FUNNEL_QUERY } from './webFunnel';
import { IS_ELECTRON } from './windowEnvironment';

export async function captureBrowserWebFunnel(hasAccounts: boolean): Promise<WebFunnelContext | undefined> {
  if (IS_AIR_APP || IS_EXPLORER || IS_EXTENSION || IS_TELEGRAM_APP || IS_ELECTRON
    || !isWebFunnelOrigin(location.origin)) return undefined;
  try {
    const context = {
      visitId: getWebFunnelVisitId(location.search),
      hasExistingState: hasAccounts || typeof localStorage.getItem(GLOBAL_STATE_CACHE_KEY) === 'string',
    };
    const saved = await mutateWebFunnelStorage((items) => ({
      ...items, webFunnelHandoff: items.webFunnelHandoff ?? context,
    }));
    const url = new URL(location.href);
    url.searchParams.delete(WEB_FUNNEL_QUERY);
    history.replaceState(history.state, '', url.href);
    return { ...saved.webFunnelHandoff!, hasExistingState: context.hasExistingState };
  } catch {
    return undefined;
  }
}

let retryInstalled = false;
export function setupWebFunnelRetry(retry: NoneToVoidFunction) {
  if (retryInstalled || IS_AIR_APP || IS_EXPLORER || IS_EXTENSION || IS_TELEGRAM_APP || IS_ELECTRON
    || !isWebFunnelOrigin(location.origin)) return;
  retryInstalled = true;
  window.addEventListener('online', retry);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') retry();
  });
}
