jest.mock('electron', () => ({
  app: {
    isPackaged: true,
    getPath: jest.fn(() => '/test/userData'),
  },
}));

jest.mock('electron-conf/main', () => ({
  Conf: jest.fn(),
}));

import { pathToFileURL } from 'url';

import { PRODUCTION_URL } from '../config';
import { checkIsExternalUrlAllowed, checkIsWebContentsUrlAllowed } from './utils';

const LOCAL_CONTENTS_URL = pathToFileURL(`${__dirname}/index.html`);

describe('checkIsWebContentsUrlAllowed', () => {
  it('allows the packaged local file', () => {
    expect(checkIsWebContentsUrlAllowed(LOCAL_CONTENTS_URL.href)).toBe(true);
  });

  it('rejects an untrusted origin with the same pathname as the packaged local file', () => {
    const url = new URL(LOCAL_CONTENTS_URL.pathname, 'https://evil.example');

    expect(checkIsWebContentsUrlAllowed(url.href)).toBe(false);
  });

  it('allows a remote URL from an allowed origin', () => {
    expect(checkIsWebContentsUrlAllowed(`${PRODUCTION_URL}/index.html`)).toBe(true);
  });
});

describe('checkIsExternalUrlAllowed', () => {
  it.each([
    'http://example.com',
    'https://example.com/path?query=1',
    'mailto:support@example.com',
  ])('allows %s', (url) => {
    expect(checkIsExternalUrlAllowed(url)).toBe(true);
  });

  it.each([
    'javascript:alert(1)',
    'data:text/html,hello',
    'file:///C:/Windows/System32/calc.exe',
    'smb://host/share',
    'ms-msdt:/id PCWDiagnostic',
    'search-ms:query=calc',
    'myapp://open',
    'not a url',
    '',
    '//example.com',
  ])('rejects %s', (url) => {
    expect(checkIsExternalUrlAllowed(url)).toBe(false);
  });
});
