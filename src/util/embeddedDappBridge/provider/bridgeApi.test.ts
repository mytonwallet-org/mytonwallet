import { getActions } from '../../../global';

import { openDeeplinkOrUrl } from '../../deeplink';
import { buildBridgeApi } from './bridgeApi';

jest.mock('../../../global', () => ({
  getActions: jest.fn(),
  setGlobal: jest.fn(),
}));

jest.mock('../../deeplink', () => ({
  openDeeplinkOrUrl: jest.fn(),
}));

jest.mock('./tonConnectBridgeApi', () => ({
  buildTonConnectBridgeApi: jest.fn(),
}));

jest.mock('./solanaConnectBridgeApi', () => ({
  buildSolanaConnectBridgeApi: jest.fn(),
}));

jest.mock('./evmConnectBridgeApi', () => ({
  buildEvmConnectBridgeApi: jest.fn(() => ({})),
}));

describe('buildBridgeApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    (getActions as jest.Mock).mockReturnValue({
      closeBrowser: jest.fn(),
    });
  });

  it('should mark window open deeplinks as in-app browser sourced', () => {
    const bridgeApi = buildBridgeApi('https://trusted.example');
    const url = 'mtw://offramp?depositWalletAddress=UQAddress&baseCurrencyCode=ton';

    bridgeApi['window:open']({ url });

    expect(openDeeplinkOrUrl).toHaveBeenCalledWith(url, {
      isExternal: true,
      isFromInAppBrowser: true,
    });
  });
});
