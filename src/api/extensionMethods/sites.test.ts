import { getCurrentAccountIdOrFail, waitLogin } from '../common/accounts';
import { initSiteMethods, processDeeplink } from './sites';
import { openPopupWindow } from './window';

jest.mock('../common/accounts', () => ({
  getCurrentAccountIdOrFail: jest.fn(),
  waitLogin: jest.fn(),
}));

jest.mock('../common/dappPromises', () => ({
  resolveDappPromise: jest.fn(),
}));

jest.mock('../methods/analytics', () => ({
  recordTonConnectEvent: jest.fn(),
}));

jest.mock('../storages/extension', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(),
  },
}));

jest.mock('./window', () => ({
  clearCache: jest.fn(),
  openPopupWindow: jest.fn(),
}));

describe('extension site methods', () => {
  let onPopupUpdate: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();

    onPopupUpdate = jest.fn();

    (getCurrentAccountIdOrFail as jest.Mock).mockResolvedValue('test-account-id');
    (openPopupWindow as jest.Mock).mockResolvedValue(undefined);
    (waitLogin as jest.Mock).mockResolvedValue(undefined);

    initSiteMethods(onPopupUpdate);
  });

  it('should mark page deeplinks as in-app browser sourced', async () => {
    const url = 'mtw://offramp?depositWalletAddress=UQAddress&baseCurrencyCode=ton';

    await processDeeplink({ url });

    expect(getCurrentAccountIdOrFail).toHaveBeenCalled();
    expect(openPopupWindow).toHaveBeenCalled();
    expect(waitLogin).toHaveBeenCalled();
    expect(onPopupUpdate).toHaveBeenCalledWith({
      type: 'processDeeplink',
      url,
      isFromInAppBrowser: true,
    });
  });
});
