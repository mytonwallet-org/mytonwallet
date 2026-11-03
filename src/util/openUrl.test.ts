import { openUrl } from './openUrl';

jest.mock('./windowEnvironment', () => ({
  ...jest.requireActual('./windowEnvironment'),
  IS_ELECTRON: true,
}));

describe('openUrl in Electron', () => {
  const windowOpen = jest.spyOn(window, 'open').mockImplementation();

  beforeEach(() => {
    windowOpen.mockClear();
  });

  it.each([
    'https://example.com/',
    'http://example.com/',
    'mailto:support@example.com',
  ])('opens %s externally', async (url) => {
    await openUrl(url, { isExternal: true });

    expect(windowOpen).toHaveBeenCalledWith(url, '_blank', 'noopener');
  });

  it.each([
    'javascript:alert(1)',
    'file:///C:/Windows/System32/calc.exe',
    'ms-msdt:/id PCWDiagnostic',
    'myapp://back',
  ])('does not open %s', async (url) => {
    await openUrl(url, { isExternal: true });

    expect(windowOpen).not.toHaveBeenCalled();
  });
});
