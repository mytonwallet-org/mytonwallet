import { getGateBase, shouldStartUpdater } from './updateChannel';

describe('shouldStartUpdater', () => {
  it('starts on production regardless of platform/preview', () => {
    expect(shouldStartUpdater({ isProduction: true, isStaging: false, isPreview: false, isMacOs: false })).toBe(true);
    expect(shouldStartUpdater({ isProduction: true, isStaging: false, isPreview: true, isMacOs: false })).toBe(true);
  });

  it('starts on a non-preview macOS staging shell', () => {
    expect(shouldStartUpdater({ isProduction: false, isStaging: true, isPreview: false, isMacOs: true })).toBe(true);
  });

  it('stays off for preview staging (release/** builds load file://)', () => {
    expect(shouldStartUpdater({ isProduction: false, isStaging: true, isPreview: true, isMacOs: true })).toBe(false);
  });

  it('stays off for non-mac staging (hand-distributed win/linux, no feed)', () => {
    expect(shouldStartUpdater({ isProduction: false, isStaging: true, isPreview: false, isMacOs: false })).toBe(false);
  });

  it('stays off for development', () => {
    expect(shouldStartUpdater({ isProduction: false, isStaging: false, isPreview: false, isMacOs: true })).toBe(false);
  });
});

describe('getGateBase', () => {
  it('polls the beta feed base for staging', () => {
    expect(getGateBase({ isStaging: true, betaUpdateUrl: 'https://beta', productionUrl: 'https://prod' }))
      .toBe('https://beta');
  });

  it('polls the production url otherwise (byte-identical to today)', () => {
    expect(getGateBase({ isStaging: false, betaUpdateUrl: 'https://beta', productionUrl: 'https://prod' }))
      .toBe('https://prod');
  });
});
