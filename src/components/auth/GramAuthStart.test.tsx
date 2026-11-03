import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { APP_PRIVACY_POLICY_URL, APP_TERMS_OF_USE_URL } from '../../config';
import { pause } from '../../util/schedulers';
import * as environment from '../../util/windowEnvironment';

import GramAuthStart from './GramAuthStart';

const mockCreateWallet = jest.fn();
const mockImportWallet = jest.fn();

jest.mock('../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../util/windowEnvironment'),
  __esModule: true,
  IS_IOS: false,
  IS_ANDROID: false,
}));

jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  getActions: () => ({
    startCreatingWallet: mockCreateWallet,
    openAuthImportWalletModal: mockImportWallet,
  }),
}));

jest.mock('../common/GramDiamond', () => () => undefined);
jest.mock('./WelcomeParticles', () => () => undefined);

describe('Gram welcome downloads', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  async function renderWelcome(platform = 'desktop') {
    jest.replaceProperty(environment, 'IS_IOS', platform === 'ios');
    jest.replaceProperty(environment, 'IS_ANDROID', platform === 'android');
    TeactDOM.render(<GramAuthStart isActive />, root);
    await pause(50);
  }

  it.each([
    ['desktop', true, true, true],
    ['ios', true, false, false],
    ['android', false, true, false],
  ])('offers the correct downloads on %s', async (platform, hasApple, hasGoogle, hasQr) => {
    await renderWelcome(platform);

    expect(Boolean(root.querySelector('a[aria-label="App Store"]'))).toBe(hasApple);
    expect(Boolean(root.querySelector('a[aria-label="Google Play"]'))).toBe(hasGoogle);
    const source = platform === 'desktop' ? 'desktop_app' : 'mobile_web';
    if (hasApple) {
      expect(root.querySelector('a[aria-label="App Store"]')?.getAttribute('href'))
        .toBe(`https://gramwallet.io/ios-store?utm_source=${source}`);
    }
    if (hasGoogle) {
      expect(root.querySelector('a[aria-label="Google Play"]')?.getAttribute('href'))
        .toBe(`https://gramwallet.io/android-store?utm_source=${source}`);
    }
    expect(Boolean(root.querySelector('a[aria-label="Scan QR"]'))).toBe(hasQr);
  });

  it('opens creation and import without a responsibility checkbox', async () => {
    await renderWelcome();
    expect(root.querySelector('input[type="checkbox"]')).toBeNull();

    const buttons = Array.from(root.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.includes('Create New Wallet'))!.click();
    buttons.find((button) => button.textContent?.includes('Import Existing Wallet'))!.click();

    expect(mockCreateWallet).toHaveBeenCalledTimes(1);
    expect(mockImportWallet).toHaveBeenCalledTimes(1);
    expect(root.querySelector(`a[href="${APP_TERMS_OF_USE_URL}"]`)).not.toBeNull();
    expect(root.querySelector(`a[href="${APP_PRIVACY_POLICY_URL}"]`)).not.toBeNull();
  });

  it('links the QR button directly to the mobile install page', async () => {
    await renderWelcome();
    const link = root.querySelector<HTMLAnchorElement>('a[aria-label="Scan QR"]')!;

    expect(link.href).toBe('https://get.gramwallet.io/?utm_source=desktop_app');
    expect(link.target).toBe('_blank');
  });
});
