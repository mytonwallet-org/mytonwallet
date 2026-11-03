import type { HandlerDetails, Session, WindowOpenHandlerResponse } from 'electron';
import { shell } from 'electron';

import { checkIsExternalUrlAllowed, checkIsWebContentsUrlAllowed } from './utils';

type PermissionRequestHandler = NonNullable<Parameters<Session['setPermissionRequestHandler']>[0]>;
type PermissionName = Parameters<PermissionRequestHandler>[1];
type PermissionDetails = Parameters<PermissionRequestHandler>[3];

type RedirectEvent = Pick<Electron.Event<Electron.WebContentsWillRedirectEventParams>,
  'isMainFrame' | 'url' | 'preventDefault'>;

export function handleWindowOpen({ url }: Pick<HandlerDetails, 'url'>): WindowOpenHandlerResponse {
  if (checkIsExternalUrlAllowed(url)) {
    void shell.openExternal(url);
  }

  return { action: 'deny' };
}

export function preventDisallowedRedirect(event: RedirectEvent) {
  if (event.isMainFrame && !checkIsWebContentsUrlAllowed(event.url)) {
    event.preventDefault();
  }
}

// A frame navigating to a scheme the browser cannot load asks for `openExternal`; every other permission
// is granted, which is what Electron does without a handler
export function checkIsPermissionRequestAllowed(permission: PermissionName, details: PermissionDetails): boolean {
  if (permission !== 'openExternal') {
    return true;
  }

  const externalUrl = 'externalURL' in details ? details.externalURL : undefined;

  return externalUrl !== undefined && checkIsExternalUrlAllowed(externalUrl);
}

export const handlePermissionRequest: PermissionRequestHandler = (webContents, permission, callback, details) => {
  callback(checkIsPermissionRequestAllowed(permission, details));
};
