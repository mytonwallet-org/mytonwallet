import { isSubproject, openUrl } from './openUrl';

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

describe('isSubproject', () => {
  it('accepts a subproject host', () => {
    expect(isSubproject('https://multisend.mywallet.io/')).toBe(true);
    expect(isSubproject('https://example.com/')).toBe(false);
  });

  it('accepts a subproject served from localhost outside production', async () => {
    const { isSubproject: isSubprojectInDevelopment } = await importOpenUrlFor('development');

    expect(isSubprojectInDevelopment('http://localhost:4323/')).toBe(true);
  });

  // A subproject page receives the addresses of the current account in its URL
  it('rejects localhost in a production build', async () => {
    const { isSubproject: isSubprojectInProduction } = await importOpenUrlFor('production');

    expect(isSubprojectInProduction('http://localhost:4323/')).toBe(false);
    expect(isSubprojectInProduction('https://multisend.mywallet.io/')).toBe(true);
  });
});

async function importOpenUrlFor(appEnv: string) {
  const previousAppEnv = process.env.APP_ENV;
  process.env.APP_ENV = appEnv;

  let module: typeof import('./openUrl') | undefined;
  try {
    await jest.isolateModulesAsync(async () => {
      module = await import('./openUrl');
    });
  } finally {
    if (previousAppEnv === undefined) {
      delete process.env.APP_ENV;
    } else {
      process.env.APP_ENV = previousAppEnv;
    }
  }

  return module!;
}
