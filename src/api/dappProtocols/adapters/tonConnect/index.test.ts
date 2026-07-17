import { DappProtocolType } from '../../types';

import { createTonConnectAdapter } from './index';

const mockFetchJsonWithProxy = jest.fn();
const mockFetchStoredChainAccount = jest.fn();
const mockGetCurrentAccountId = jest.fn();
const mockCreateDappPromise = jest.fn();
const mockAddDapp = jest.fn();
const mockTonConnectGetDeviceInfo = jest.fn();
const mockGetWalletStateInit = jest.fn();
const mockToRawAddress = jest.fn();

jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  IS_AIR_APP: false,
  IS_EXTENSION: false,
  SSE_BRIDGE_URL: 'https://bridge.example/',
}));

jest.mock('../../../../util/fetch', () => ({
  fetchJsonWithProxy: (...args: unknown[]) => mockFetchJsonWithProxy(...args),
  handleFetchErrors: jest.fn(),
}));

jest.mock('../../../../util/tonConnectEnvironment', () => ({
  tonConnectGetDeviceInfo: (...args: unknown[]) => mockTonConnectGetDeviceInfo(...args),
}));

jest.mock('../../../chains/ton/wallet', () => ({
  getContractInfo: jest.fn(),
  getWalletPublicKey: jest.fn(),
  getWalletStateInit: (...args: unknown[]) => mockGetWalletStateInit(...args),
}));

jest.mock('../../../common/accounts', () => ({
  fetchStoredChainAccount: (...args: unknown[]) => mockFetchStoredChainAccount(...args),
  getCurrentAccountId: (...args: unknown[]) => mockGetCurrentAccountId(...args),
  getCurrentAccountIdOrFail: jest.fn(),
  getCurrentNetwork: jest.fn(),
  waitLogin: jest.fn(),
}));

jest.mock('../../../common/dappPromises', () => ({
  createDappPromise: (...args: unknown[]) => mockCreateDappPromise(...args),
}));

jest.mock('../../../methods/dapps', () => ({
  addDapp: (...args: unknown[]) => mockAddDapp(...args),
  deleteDapp: jest.fn(),
  findLastConnectedAccount: jest.fn(),
  getDapp: jest.fn(),
  getDappsState: jest.fn(),
  getSseLastEventId: jest.fn(),
  setSseLastEventId: jest.fn(),
  updateDapp: jest.fn(),
}));

jest.mock('../../../methods', () => ({
  createLocalActivitiesFromEmulation: jest.fn(),
  createLocalTransactions: jest.fn(),
}));

jest.mock('../../../chains', () => ({
  __esModule: true,
  default: {},
  chains: {},
}));

jest.mock('../../../chains/ton/transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  sendSignedTransactions: jest.fn(),
}));

jest.mock('../../../chains/ton/util/metadata', () => ({
  parsePayloadBase64: jest.fn(),
}));

jest.mock('../../../chains/ton/util/tonCore', () => ({
  getIsRawAddress: jest.fn(),
  getWalletPublicKey: jest.fn(),
  toBase64Address: jest.fn((address: string) => address),
  toRawAddress: (...args: unknown[]) => mockToRawAddress(...args),
}));

jest.mock('../../../common/helpers', () => ({
  isUpdaterAlive: jest.fn(() => true),
}));

jest.mock('../../../hooks', () => ({
  callHook: jest.fn(),
}));

describe('TonConnectAdapter.connect', () => {
  const activeAccountId = '0-mainnet';
  const selectedAccountId = '1-mainnet';
  const activeAddress = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA-active';
  const selectedAddress = 'UQBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB-selected';

  const activeAccount = {
    type: 'mnemonic',
    byChain: {
      ton: {
        address: activeAddress,
        publicKey: 'active-public-key',
      },
    },
  };

  const selectedAccount = {
    type: 'mnemonic',
    byChain: {
      ton: {
        address: selectedAddress,
        publicKey: 'selected-public-key',
      },
    },
  };

  beforeEach(() => {
    jest.clearAllMocks();

    mockFetchJsonWithProxy.mockResolvedValue({
      url: 'https://agents.ton.org',
      name: 'Agents',
      iconUrl: 'https://agents.ton.org/icon.png',
    });
    mockGetCurrentAccountId.mockResolvedValue(activeAccountId);
    mockFetchStoredChainAccount.mockImplementation((accountId: string) => (
      accountId === selectedAccountId ? selectedAccount : activeAccount
    ));
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve({ accountId: selectedAccountId }),
    });
    mockTonConnectGetDeviceInfo.mockReturnValue({
      platform: 'browser',
      appName: 'MyTonWallet',
    });
    mockGetWalletStateInit.mockImplementation((wallet) => ({
      toBoc: () => Buffer.from(`state:${wallet.address}`),
    }));
    mockToRawAddress.mockImplementation((address: string) => `raw:${address}`);
  });

  it('uses the wallet selected in the connect modal, not the initially active wallet', async () => {
    const adapter = createTonConnectAdapter();
    const onUpdate = jest.fn();
    await adapter.init({
      onUpdate,
      env: { isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} } },
      chainDappSupports: {},
    });

    const result = await adapter.connect(
      {
        url: undefined,
        identifier: 'request-1',
        sseOptions: {
          clientId: 'wallet-client-id',
          appClientId: 'app-client-id',
          secretKey: 'secret-key',
          lastOutputId: 0,
        },
      },
      {
        protocolType: DappProtocolType.TonConnect,
        transport: 'sse',
        requestedChains: [{ chain: 'ton', network: 'mainnet' }],
        permissions: {
          isAddressRequired: true,
          isPasswordRequired: false,
        },
        protocolData: {
          manifestUrl: 'https://agents.ton.org/tonconnect-manifest.json',
          items: [{ name: 'ton_addr' }],
        },
      },
      123,
    );

    expect(result.success).toBe(true);
    if (!result.success) return;

    expect(result.session.accountId).toBe(selectedAccountId);
    expect(result.session.chains).toEqual([{
      chain: 'ton',
      address: selectedAddress,
      network: 'mainnet',
    }]);
    expect((result.session.protocolData.payload as any).items).toEqual([
      expect.objectContaining({
        name: 'ton_addr',
        address: `raw:${selectedAddress}`,
        publicKey: 'selected-public-key',
      }),
    ]);
    expect((result.session.dapp as any).chains).toEqual([{
      chain: 'ton',
      address: selectedAddress,
      network: 'mainnet',
    }]);
    expect(mockTonConnectGetDeviceInfo).toHaveBeenCalledWith(selectedAccount);
    expect(mockAddDapp).toHaveBeenCalledWith(
      selectedAccountId,
      expect.objectContaining({
        url: 'https://agents.ton.org',
        chains: [{ chain: 'ton', address: selectedAddress, network: 'mainnet' }],
        sse: expect.objectContaining({ appClientId: 'app-client-id' }),
      }),
      'app-client-id',
    );
    expect(mockFetchStoredChainAccount).toHaveBeenCalledWith(activeAccountId, 'ton');
    expect(mockFetchStoredChainAccount).toHaveBeenCalledWith(selectedAccountId, 'ton');
  });
});
