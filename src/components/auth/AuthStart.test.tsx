import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import { getGlobal, setGlobal } from '../../global';

import { APP_PRIVACY_POLICY_URL, APP_TERMS_OF_USE_URL } from '../../config';
import { pause } from '../../util/schedulers';
import * as environment from '../../util/windowEnvironment';

import AuthStart from './AuthStart';

const mockCreateWallet = jest.fn();
const mockImportWallet = jest.fn();

jest.mock('../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../util/windowEnvironment'),
  __esModule: true,
  IS_NEW_WALLET_CREATION_HIDDEN: false,
}));
jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  getActions: () => ({
    startCreatingWallet: mockCreateWallet,
    openAuthImportWalletModal: mockImportWallet,
  }),
}));
jest.mock('./WelcomeParticles', () => () => undefined);

describe('My Wallet welcome', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  async function render(isLoading = false) {
    const global = getGlobal();
    setGlobal({ ...global, auth: { ...global.auth, isLoading } });
    TeactDOM.render(<AuthStart isActive />, root);
    await pause(50);
    return Array.from(root.querySelectorAll('button'));
  }

  it('opens both flows immediately and displays the brand legal links without a checkbox', async () => {
    const buttons = await render();
    expect(root.querySelector('input[type="checkbox"]')).toBeNull();
    buttons.find((button) => button.textContent?.includes('Create New Wallet'))!.click();
    buttons.find((button) => button.textContent?.includes('Import Existing Wallet'))!.click();
    expect(mockCreateWallet).toHaveBeenCalledTimes(1);
    expect(mockImportWallet).toHaveBeenCalledTimes(1);
    expect(root.querySelector(`a[href="${APP_TERMS_OF_USE_URL}"]`)).not.toBeNull();
    expect(root.querySelector(`a[href="${APP_PRIVACY_POLICY_URL}"]`)).not.toBeNull();
  });

  it('prevents both actions during loading', async () => {
    const buttons = await render(true);
    const create = buttons.find((button) => button.textContent?.includes('Create New Wallet'))!;
    const importWallet = buttons.find((button) => button.textContent?.includes('Import Existing Wallet'))!;
    expect(create.disabled).toBe(true);
    expect(importWallet.disabled).toBe(true);
    create.click();
    importWallet.click();
    expect(mockCreateWallet).not.toHaveBeenCalled();
    expect(mockImportWallet).not.toHaveBeenCalled();
  });

  it('keeps wallet creation hidden on legacy hosts', async () => {
    jest.replaceProperty(environment, 'IS_NEW_WALLET_CREATION_HIDDEN', true);
    const buttons = await render();
    expect(buttons.some((button) => button.textContent?.includes('Create New Wallet'))).toBe(false);
    expect(buttons.find((button) => button.textContent?.includes('Import Existing Wallet'))!.disabled).toBe(false);
    expect(root.querySelector(`a[href="${APP_TERMS_OF_USE_URL}"]`)).not.toBeNull();
  });
});
