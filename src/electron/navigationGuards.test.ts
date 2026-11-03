const mockOpenExternal = jest.fn();

jest.mock('electron', () => ({
  app: {
    isPackaged: true,
    getPath: jest.fn(() => '/test/userData'),
  },
  shell: {
    openExternal: (...args: unknown[]) => mockOpenExternal(...args),
  },
}));

jest.mock('electron-conf/main', () => ({
  Conf: jest.fn(),
}));

import { PRODUCTION_URL } from '../config';
import {
  checkIsPermissionRequestAllowed,
  handlePermissionRequest,
  handleWindowOpen,
  preventDisallowedRedirect,
} from './navigationGuards';

const REQUEST_DETAILS = { isMainFrame: false, requestingUrl: 'https://iframe.example/' };

describe('handleWindowOpen', () => {
  beforeEach(() => {
    mockOpenExternal.mockClear();
  });

  it.each([
    'https://example.com/',
    'mailto:support@example.com',
  ])('opens %s externally and denies the window', (url) => {
    expect(handleWindowOpen({ url })).toEqual({ action: 'deny' });
    expect(mockOpenExternal).toHaveBeenCalledWith(url);
  });

  it.each([
    'ms-msdt:/id PCWDiagnostic',
    'file:///C:/Windows/System32/calc.exe',
    'myapp://back',
  ])('does not open %s and denies the window', (url) => {
    expect(handleWindowOpen({ url })).toEqual({ action: 'deny' });
    expect(mockOpenExternal).not.toHaveBeenCalled();
  });
});

describe('preventDisallowedRedirect', () => {
  function redirect(url: string, isMainFrame: boolean) {
    const event = { url, isMainFrame, preventDefault: jest.fn() };
    preventDisallowedRedirect(event);
    return event.preventDefault;
  }

  it('blocks a main-frame redirect to another origin', () => {
    expect(redirect('https://evil.example/', true)).toHaveBeenCalled();
  });

  it('allows a main-frame redirect to a wallet origin', () => {
    expect(redirect(`${PRODUCTION_URL}/index.html`, true)).not.toHaveBeenCalled();
  });

  it('allows a subframe redirect to another origin', () => {
    expect(redirect('https://evil.example/', false)).not.toHaveBeenCalled();
  });
});

describe('checkIsPermissionRequestAllowed', () => {
  it.each([
    'http://example.com/',
    'https://example.com/',
    'mailto:support@example.com',
  ])('allows opening %s externally', (externalURL) => {
    expect(checkIsPermissionRequestAllowed('openExternal', { ...REQUEST_DETAILS, externalURL })).toBe(true);
  });

  it.each([
    'ms-msdt:/id PCWDiagnostic',
    'file:///C:/Windows/System32/calc.exe',
    'myapp://back',
  ])('refuses opening %s externally', (externalURL) => {
    expect(checkIsPermissionRequestAllowed('openExternal', { ...REQUEST_DETAILS, externalURL })).toBe(false);
  });

  it('refuses opening externally without a URL', () => {
    expect(checkIsPermissionRequestAllowed('openExternal', REQUEST_DETAILS)).toBe(false);
  });

  it('grants other permissions', () => {
    expect(checkIsPermissionRequestAllowed('media', { ...REQUEST_DETAILS, mediaTypes: ['audio'] })).toBe(true);
  });

  it('answers the request through the callback', () => {
    const callback = jest.fn();

    handlePermissionRequest(
      {} as Electron.WebContents,
      'openExternal',
      callback,
      { ...REQUEST_DETAILS, externalURL: 'ms-msdt:/id PCWDiagnostic' },
    );

    expect(callback).toHaveBeenCalledWith(false);
  });
});
