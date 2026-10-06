import { beginCell } from '@ton/core';
import nacl from 'tweetnacl';

import type { ApiUpdateDappSendTransactions } from '../../../types';
import { DappProtocolType } from '../../types';

import { SEND_TRANSACTION_ERROR_CODES } from './errors';
import { createTonConnectAdapter } from './index';

const mockFetchJsonWithProxy = jest.fn();
const mockFetchStoredChainAccount = jest.fn();
const mockGetCurrentAccountId = jest.fn();
const mockCreateDappPromise = jest.fn();
const mockAddDapp = jest.fn();
const mockGetDapp = jest.fn();
const mockCheckMultiTransactionDraft = jest.fn();
const mockTonConnectGetDeviceInfo = jest.fn();
const mockGetWalletStateInit = jest.fn();
const mockToRawAddress = jest.fn();
const mockParsePayloadBase64 = jest.fn();

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
  getDapp: (...args: unknown[]) => mockGetDapp(...args),
  getDappsState: jest.fn(),
  getSseLastEventId: jest.fn(),
  setSseLastEventId: jest.fn(),
  updateDapp: jest.fn(),
}));

jest.mock('../../../methods', () => ({
  createLocalTransactions: jest.fn(),
}));

jest.mock('../../../chains', () => ({
  __esModule: true,
  default: {},
  chains: {},
}));

jest.mock('../../../chains/ton/transfer', () => ({
  checkMultiTransactionDraft: (...args: unknown[]) => mockCheckMultiTransactionDraft(...args),
  sendSignedTransactions: jest.fn(),
}));

jest.mock('../../../chains/ton/util/metadata', () => ({
  parsePayloadBase64: (...args: unknown[]) => mockParsePayloadBase64(...args),
  preloadPayloadNfts: jest.fn(() => Promise.resolve(undefined)),
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
  const rotationAnchorKeyPair = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(1)));
  const rotationSigningKeyPair = nacl.sign.keyPair.fromSeed(new Uint8Array(Array(32).fill(2)));
  const rotationAnchorPublicKey = Buffer.from(rotationAnchorKeyPair.publicKey).toString('hex');
  const rotationSigningPublicKey = Buffer.from(rotationSigningKeyPair.publicKey).toString('hex');

  const activeAccount = {
    type: 'mnemonic',
    byChain: {
      ton: {
        address: activeAddress,
        publicKey: 'active-public-key',
        version: 'W5',
      },
    },
  };

  const selectedAccount = {
    type: 'mnemonic',
    byChain: {
      ton: {
        address: selectedAddress,
        publicKey: 'selected-public-key',
        version: 'W5',
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

  async function createConnectedAdapter() {
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate: jest.fn(),
      env: {
        agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} },
      },
      chainDappSupports: {},
    });

    return adapter;
  }

  function connect(
    adapter: Awaited<ReturnType<typeof createConnectedAdapter>>,
    items = [{ name: 'ton_addr' }] as Array<{ name: 'ton_addr' } | { name: 'ton_proof'; payload: string }>,
  ) {
    return adapter.connect(
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
          items,
        },
      },
      123,
    );
  }

  it('uses the wallet selected in the connect modal, not the initially active wallet', async () => {
    const adapter = await createConnectedAdapter();

    const result = await connect(adapter);

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

  it('uses the signing public key for rotated Telegram proof and keeps state init from anchor', async () => {
    const rotatedTelegramAccount = {
      type: 'bip39',
      byChain: {
        ton: {
          address: selectedAddress,
          publicKey: rotationAnchorPublicKey,
          version: 'telegram',
          index: 0,
        },
      },
    };
    mockFetchStoredChainAccount.mockImplementation((accountId: string) => (
      accountId === selectedAccountId ? rotatedTelegramAccount : activeAccount
    ));
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve({
        accountId: selectedAccountId,
        proofSignatures: ['proof-signature'],
        proofPublicKeys: [rotationSigningPublicKey],
      }),
    });

    const result = await connect(await createConnectedAdapter(), [
      { name: 'ton_addr' },
      { name: 'ton_proof', payload: 'rotation-proof' },
    ]);

    expect(result.success).toBe(true);
    if (!result.success) return;

    const items = (result.session.protocolData.payload as any).items;
    expect(items).toEqual(expect.arrayContaining([
      expect.objectContaining({
        name: 'ton_addr',
        publicKey: rotationSigningPublicKey,
      }),
      expect.objectContaining({
        name: 'ton_proof',
      }),
    ]));
    expect(mockGetWalletStateInit).toHaveBeenCalledWith(expect.objectContaining({
      publicKey: rotationAnchorPublicKey,
      version: 'telegram',
    }));
  });

  it.each(['publicKey', 'version'] as const)('refuses to connect a wallet with no %s', async (field) => {
    mockFetchStoredChainAccount.mockResolvedValue({
      ...selectedAccount,
      byChain: { ton: { ...selectedAccount.byChain.ton, [field]: undefined } },
    });

    const result = await connect(await createConnectedAdapter());

    // Without either one the reply cannot be built, and the dapp is told what is wrong instead of getting
    // an unknown error from a failure deeper in the wallet code
    expect(result.success).toBe(false);
    if (result.success) return;

    expect(result.error.code).toBe(SEND_TRANSACTION_ERROR_CODES.BAD_REQUEST_ERROR);
  });
});

describe('TonConnectAdapter.sendTransaction', () => {
  const accountId = '0-mainnet';
  const walletAddress = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const contractAddress = 'EQBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
  const payloadRecipientAddress = 'EQCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetDapp.mockResolvedValue({
      url: 'https://example.com',
      name: 'Example',
      iconUrl: 'https://example.com/icon.png',
      manifestUrl: 'https://example.com/tonconnect-manifest.json',
    });
    mockFetchStoredChainAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: {
        ton: {
          address: walletAddress,
          publicKey: '00'.repeat(32),
          version: 'W5',
        },
      },
    });
    mockCheckMultiTransactionDraft.mockResolvedValue({
      emulation: {
        isFallback: true,
        networkFee: 1n,
      },
      parsedPayloads: [{
        type: 'tokens:transfer',
        queryId: 1n,
        amount: 2n,
        destination: 'unvalidated-recipient',
        responseDestination: walletAddress,
        forwardAmount: 0n,
        slug: 'ton-token',
        tokenAddress: 'token-address',
      }],
    });
    mockParsePayloadBase64.mockResolvedValue({
      type: 'tokens:transfer',
      queryId: 1n,
      amount: 2n,
      destination: payloadRecipientAddress,
      responseDestination: walletAddress,
      forwardAmount: 0n,
      slug: 'ton-token',
      tokenAddress: 'token-address',
    });
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: new Promise(() => {}),
    });
  });

  it('revalidates the raw payload and keeps the message destination as the primary address', async () => {
    let resolveUpdate!: (update: ApiUpdateDappSendTransactions) => void;
    const updatePromise = new Promise<ApiUpdateDappSendTransactions>((resolve) => {
      resolveUpdate = resolve;
    });
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate: (update) => {
        if (update.type === 'dappSendTransactions') {
          resolveUpdate(update);
        }
      },
      env: {
        agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} },
      },
      chainDappSupports: {},
    });

    void adapter.sendTransaction(
      { url: 'https://example.com', accountId },
      {
        id: 'request-1',
        chain: 'ton',
        payload: {
          messages: [{
            address: contractAddress,
            amount: '1',
            payload: beginCell().endCell().toBoc().toString('base64'),
          }],
        },
      },
    );

    const update = await updatePromise;
    expect(update.transactions[0]).toMatchObject({
      toAddress: contractAddress,
      displayedToAddress: contractAddress,
      payload: { destination: payloadRecipientAddress },
    });
    expect(mockParsePayloadBase64).toHaveBeenCalledWith(
      'mainnet', contractAddress, expect.any(String), { expectedOwnerAddress: walletAddress },
    );
  });
});
