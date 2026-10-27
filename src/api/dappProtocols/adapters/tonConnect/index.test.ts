import { beginCell } from '@ton/core';
import nacl from 'tweetnacl';

import { ApiCommonError, type ApiUpdate, type ApiUpdateDappSendTransactions } from '../../../types';
import { DappProtocolType } from '../../types';

import { FetchDemand } from '../../../../util/fetchDemand';
import { SEND_TRANSACTION_ERROR_CODES } from './errors';
import { createTonConnectAdapter } from './index';

const mockFetchJsonWithProxy = jest.fn();
const mockFetchStoredChainAccount = jest.fn();
const mockGetCurrentAccountId = jest.fn();
const mockCreateDappPromise = jest.fn();
const mockAddDapp = jest.fn();
const mockGetDapp = jest.fn();
const mockSetSseDelivery = jest.fn();
const mockCheckMultiTransactionDraft = jest.fn();
const mockSendSignedTransactions = jest.fn();
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
  getSseDelivery: jest.fn(),
  getSseLastEventId: jest.fn(),
  setSseDelivery: (...args: unknown[]) => mockSetSseDelivery(...args),
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
  sendSignedTransactions: (...args: unknown[]) => mockSendSignedTransactions(...args),
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
  const proofSignature = Buffer.alloc(64, 1).toString('base64');
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
    jest.replaceProperty(jest.requireMock('../../../../config'), 'IS_AIR_APP', false);

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

  async function createConnectedAdapter(onUpdate = jest.fn<void, [ApiUpdate]>()) {
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate,
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

  it.each([false, true])('allows switching from a non-TON account before connecting (proof: %s)', async (withProof) => {
    mockFetchStoredChainAccount.mockImplementation((accountId: string) => {
      if (accountId === activeAccountId) {
        throw new Error(`ton wallet missing in account ${accountId}`);
      }
      return selectedAccount;
    });
    let confirm!: (value: unknown) => void;
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: new Promise((resolve) => { confirm = resolve; }),
    });
    const onUpdate = jest.fn<void, [ApiUpdate]>((update) => {
      if (update.type !== 'dappConnect') return;

      expect(update.accountId).toBe(activeAccountId);
      expect(update.dapp.chains).toEqual([{ chain: 'ton', network: 'mainnet', address: '' }]);
      expect(Boolean(update.proof)).toBe(withProof);
      expect(mockAddDapp).not.toHaveBeenCalled();
      confirm({ accountId: selectedAccountId, proofSignatures: withProof ? [proofSignature] : undefined });
    });
    const items = withProof
      ? [{ name: 'ton_addr' as const }, { name: 'ton_proof' as const, payload: 'proof-payload' }]
      : [{ name: 'ton_addr' as const }];

    const result = await connect(await createConnectedAdapter(onUpdate), items);

    expect(result).toMatchObject({
      success: true,
      session: {
        accountId: selectedAccountId,
        chains: [{ chain: 'ton', network: 'mainnet', address: selectedAddress }],
      },
    });
    expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual([
      'dappLoading', 'dappConnect', 'updateDapps', 'dappConnectComplete',
    ]);
    expect(mockAddDapp).toHaveBeenCalledWith(selectedAccountId, expect.objectContaining({
      chains: [{ chain: 'ton', network: 'mainnet', address: selectedAddress }],
    }), 'app-client-id');
  });

  it('validates the confirmed account even when it is still the incompatible current account', async () => {
    mockFetchStoredChainAccount.mockRejectedValue(new Error(`ton wallet missing in account ${activeAccountId}`));
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve({ accountId: activeAccountId }),
    });
    const onUpdate = jest.fn<void, [ApiUpdate]>();

    const result = await connect(await createConnectedAdapter(onUpdate));

    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({ type: 'dappConnect' }));
    expect(result).toEqual({
      success: false,
      error: { code: 0, message: `ton wallet missing in account ${activeAccountId}` },
    });
    expect(mockAddDapp).not.toHaveBeenCalled();
  });

  it('resolves the TON address when confirming the current account without switching', async () => {
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve({ accountId: activeAccountId }),
    });

    const result = await connect(await createConnectedAdapter());

    expect(result).toMatchObject({
      success: true,
      session: {
        accountId: activeAccountId,
        chains: [{ chain: 'ton', network: 'mainnet', address: activeAddress }],
      },
    });
    expect(mockAddDapp).toHaveBeenCalledWith(activeAccountId, expect.objectContaining({
      chains: [{ chain: 'ton', network: 'mainnet', address: activeAddress }],
    }), 'app-client-id');
  });

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
        proofSignatures: [proofSignature],
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
        proof: expect.objectContaining({ signature: proofSignature }),
      }),
    ]));
    expect(mockGetWalletStateInit).toHaveBeenCalledWith(expect.objectContaining({
      publicKey: rotationAnchorPublicKey,
      version: 'telegram',
    }));
  });

  it.each([
    { name: 'missing signatures', signatures: undefined },
    { name: 'empty signatures', signatures: [] },
    { name: 'an empty signature', signatures: [''] },
    { name: 'invalid base64', signatures: ['!'.repeat(88)] },
    { name: 'a short signature', signatures: [Buffer.alloc(63).toString('base64')] },
    { name: 'an oversized signature', signatures: [Buffer.alloc(65).toString('base64')] },
    { name: 'base64 with ignored characters', signatures: [`${proofSignature}\n`] },
    { name: 'extra signatures', signatures: [proofSignature, proofSignature] },
  ])('rejects $name before saving or completing the connection', async ({ signatures }) => {
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve({ accountId: selectedAccountId, proofSignatures: signatures }),
    });
    const onUpdate = jest.fn<void, [ApiUpdate]>();

    const result = await connect(await createConnectedAdapter(onUpdate), [
      { name: 'ton_addr' },
      { name: 'ton_proof', payload: 'test-proof' },
    ]);

    expect(result.success).toBe(false);
    expect(mockAddDapp).not.toHaveBeenCalled();
    expect(onUpdate.mock.calls.map(([update]) => update.type)).not.toContain('dappConnectComplete');
    expect(onUpdate.mock.calls.map(([update]) => update.type)).not.toContain('updateDapps');
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
    jest.replaceProperty(jest.requireMock('../../../../config'), 'IS_AIR_APP', false);
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
    mockSetSseDelivery.mockResolvedValue(undefined);
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
      'mainnet', contractAddress, expect.any(String), {
        expectedOwnerAddress: walletAddress,
        messageAmount: 1n,
        supportsDedustSwap: false,
        demand: expect.any(FetchDemand),
      },
    );
  });

  it('makes the provider requests of a transaction request, broadcast included, for one urgent demand', async () => {
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve([{ payload: { base64: 'signed-boc', seqno: 1 } }]),
    });
    mockSendSignedTransactions.mockResolvedValue([{ boc: 'sent-boc', msgHashNormalized: 'hash' }]);
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate: jest.fn(),
      env: {
        agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} },
      },
      chainDappSupports: {},
    });

    const result = await adapter.sendTransaction(
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

    expect(result).toMatchObject({ success: true, result: { result: 'sent-boc' } });
    const demand = mockCheckMultiTransactionDraft.mock.calls[0][5];
    expect(demand).toBeInstanceOf(FetchDemand);
    expect(demand.isUrgent()).toBe(true);
    expect(mockParsePayloadBase64.mock.calls[0][3].demand).toBe(demand);
    expect(mockSendSignedTransactions).toHaveBeenCalledWith(accountId, expect.any(Array), demand);
  });

  it.each([
    ['native iOS', true, true, false, true],
    ['native Android', true, false, true, false],
    ['web', false, false, false, false],
    ['legacy iOS web app', false, true, false, false],
  ] as const)('only enables the swap presentation on supported clients: %s', async (
    _label, isAirApp, isIosApp, isAndroidApp, supported,
  ) => {
    jest.replaceProperty(jest.requireMock('../../../../config'), 'IS_AIR_APP', isAirApp);
    // Even an already-parsed payload must not bypass the presentation capability check.
    mockParsePayloadBase64.mockResolvedValue({ type: 'dedust:native-swap' });
    let resolveUpdate!: (update: ApiUpdateDappSendTransactions) => void;
    const updatePromise = new Promise<ApiUpdateDappSendTransactions>((resolve) => {
      resolveUpdate = resolve;
    });
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate: (update) => {
        if (update.type === 'dappSendTransactions') resolveUpdate(update);
      },
      env: {
        agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false,
        isIosApp, isAndroidApp, byNetwork: { mainnet: {}, testnet: {} },
      },
      chainDappSupports: {},
    });
    const rawPayload = beginCell().endCell().toBoc().toString('base64');
    void adapter.sendTransaction({ url: 'https://example.com', accountId }, {
      id: 'swap-request', chain: 'ton',
      payload: { messages: [{ address: contractAddress, amount: '1', payload: rawPayload }] },
    });
    const update = await updatePromise;
    expect(mockParsePayloadBase64).toHaveBeenCalledWith('mainnet', contractAddress, rawPayload,
      expect.objectContaining({ supportsDedustSwap: supported }));
    expect(update.transactions[0]).toMatchObject({
      payload: supported ? { type: 'dedust:native-swap' } : { type: 'unknown', base64: rawPayload },
      isDangerous: !supported,
    });
  });

  it('does not broadcast when the settlement of its bridge event cannot be stored', async () => {
    const onUpdate = jest.fn();
    const adapter = createTonConnectAdapter();
    await adapter.init({
      onUpdate,
      env: {
        agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} },
      },
      chainDappSupports: {},
    });
    mockCreateDappPromise.mockReturnValue({
      promiseId: 'promise-1',
      promise: Promise.resolve([{ boc: 'signed' }]),
    });
    mockSetSseDelivery.mockRejectedValue(new Error('storage is unavailable'));

    const result = await adapter.sendTransaction(
      { url: 'https://example.com', accountId, sseEventId: '11' },
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

    expect(mockSendSignedTransactions).not.toHaveBeenCalled();
    expect(result).toMatchObject({ success: false, error: { code: SEND_TRANSACTION_ERROR_CODES.UNKNOWN_ERROR } });
    expect(onUpdate).toHaveBeenCalledWith({ type: 'showError', error: ApiCommonError.Unexpected });
  });
});
