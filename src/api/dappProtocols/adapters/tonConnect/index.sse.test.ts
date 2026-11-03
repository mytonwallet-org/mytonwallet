import nacl from 'tweetnacl';

import type { ApiSseDeliveryState } from '../../../types';

import { createTonConnectAdapter } from './index';

const MOCK_ACCOUNT_ID = '0-mainnet';
const MOCK_DAPP_URL = 'https://dapp.example';

const walletKeys = nacl.box.keyPair();
const dappKeys = nacl.box.keyPair();
const otherDappKeys = nacl.box.keyPair();
const toHex = (bytes: Uint8Array) => Buffer.from(bytes).toString('hex');

const mockSseOptions = {
  clientId: toHex(walletKeys.publicKey),
  appClientId: toHex(dappKeys.publicKey),
  secretKey: toHex(walletKeys.secretKey),
  lastOutputId: 0,
};

const mockStoredDapp = {
  url: MOCK_DAPP_URL,
  name: 'Dapp',
  iconUrl: `${MOCK_DAPP_URL}/icon.png`,
  manifestUrl: `${MOCK_DAPP_URL}/manifest.json`,
  connectedAt: 1,
  sse: mockSseOptions,
};

const mockStorage: { state?: ApiSseDeliveryState; lastReceivedId?: string } = {};
const mockDeferredRequests: { promiseId: string; resolve: (value: unknown) => void }[] = [];
const mockFetch = jest.fn();

// The adapter passes `Buffer`s to `tweetnacl`, and in jsdom a Node `Buffer` fails its `Uint8Array` check
jest.mock('tweetnacl', () => {
  const actual = jest.requireActual('tweetnacl');
  const toBytes = (value: unknown) => (
    value instanceof Uint8Array ? value : new Uint8Array(value as ArrayLike<number>)
  );
  const box = Object.assign(
    (...args: unknown[]) => actual.box(...args.map(toBytes)),
    actual.box,
    { open: (...args: unknown[]) => actual.box.open(...args.map(toBytes)) },
  );
  return {
    ...actual, __esModule: true, default: { ...actual, box }, box,
  };
});

jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  IS_AIR_APP: false,
  IS_EXTENSION: false,
  SSE_BRIDGE_URL: 'https://bridge.example/',
}));

jest.mock('../../../../util/fetch', () => ({
  fetchJsonWithProxy: jest.fn(),
  handleFetchErrors: jest.fn(),
}));

jest.mock('../../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  getCurrentAccountId: jest.fn(() => Promise.resolve(MOCK_ACCOUNT_ID)),
  getCurrentAccountIdOrFail: jest.fn(() => Promise.resolve(MOCK_ACCOUNT_ID)),
  getCurrentNetwork: jest.fn(() => Promise.resolve('mainnet')),
  waitLogin: jest.fn(),
}));

jest.mock('../../../common/dappPromises', () => ({
  createDappPromise: jest.fn(() => {
    let resolve!: (value: unknown) => void;
    const promise = new Promise((res) => {
      resolve = res;
    });
    const promiseId = `promise-${mockDeferredRequests.length + 1}`;
    mockDeferredRequests.push({ promiseId, resolve });
    return { promiseId, promise };
  }),
}));

jest.mock('../../../methods/dapps', () => ({
  addDapp: jest.fn(),
  deleteDapp: jest.fn(),
  findLastConnectedAccount: jest.fn(),
  getDapp: jest.fn(() => Promise.resolve(mockStoredDapp)),
  getDappsState: jest.fn(() => Promise.resolve({
    [MOCK_ACCOUNT_ID]: { [MOCK_DAPP_URL]: { [mockSseOptions.appClientId]: mockStoredDapp } },
  })),
  getSseDelivery: jest.fn(() => Promise.resolve(mockStorage.state)),
  getSseLastEventId: jest.fn(() => Promise.resolve(mockStorage.lastReceivedId)),
  setSseDelivery: jest.fn((state: ApiSseDeliveryState) => {
    mockStorage.state = state;
    return Promise.resolve();
  }),
  setSseLastEventId: jest.fn((lastReceivedId: string) => {
    mockStorage.lastReceivedId = lastReceivedId;
    return Promise.resolve();
  }),
  updateDapp: jest.fn(),
}));

jest.mock('./analytics', () => ({
  ...jest.requireActual('./analytics'),
  clearTonConnectFlowContext: jest.fn(),
  finishTonConnectFlow: jest.fn(),
  recordTonConnectEvent: jest.fn(),
  setTonConnectFlowContext: jest.fn(),
}));

jest.mock('../../../methods', () => ({}));

jest.mock('../../../chains', () => ({
  __esModule: true,
  default: {},
  chains: {},
}));

jest.mock('../../../chains/ton/transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  sendSignedTransactions: jest.fn(),
}));

jest.mock('../../../common/helpers', () => ({
  isUpdaterAlive: jest.fn(() => true),
}));

jest.mock('../../../hooks', () => ({
  callHook: jest.fn(),
}));

class FakeEventSource {
  static instances: FakeEventSource[] = [];

  readonly url: URL;

  isClosed = false;

  onopen?: () => void;

  onerror?: (event: Event) => void;

  onmessage?: (event: { data: string; lastEventId: string }) => Promise<void>;

  constructor(url: URL) {
    this.url = url;
    FakeEventSource.instances.push(this);
  }

  close() {
    this.isClosed = true;
  }

  emit(lastEventId: string, method: string, params: string[], fromKeys = dappKeys) {
    const request = Buffer.from(JSON.stringify({ id: lastEventId, method, params }));
    const nonce = nacl.randomBytes(24);
    const encrypted = nacl.box(request, nonce, walletKeys.publicKey, fromKeys.secretKey);
    const message = Buffer.concat([nonce, encrypted]).toString('base64');

    return this.onmessage!({
      data: JSON.stringify({ from: toHex(fromKeys.publicKey), message }),
      lastEventId,
    });
  }
}

const SIGN_TEXT_PARAMS = [JSON.stringify({ type: 'text', text: 'Hello' })];

async function createAdapter() {
  const onUpdate = jest.fn();
  const adapter = createTonConnectAdapter();
  await adapter.init({
    onUpdate,
    env: {
      agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: true, byNetwork: { mainnet: {}, testnet: {} },
    },
    chainDappSupports: {},
  });

  return { adapter, onUpdate, source: FakeEventSource.instances[FakeEventSource.instances.length - 1] };
}

function getSignDataUpdates(onUpdate: jest.Mock) {
  return onUpdate.mock.calls.filter(([update]) => update.type === 'dappSignData');
}

function flush() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('TonConnectAdapter SSE delivery', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    delete mockStorage.state;
    mockStorage.lastReceivedId = '10';
    mockDeferredRequests.length = 0;
    FakeEventSource.instances = [];
    (globalThis as any).EventSource = FakeEventSource;
    mockFetch.mockResolvedValue({ ok: true, status: 200 });
    globalThis.fetch = mockFetch;
  });

  it('delivers a request that was still open again after a restart', async () => {
    const first = await createAdapter();
    expect(first.source.url.searchParams.get('last_event_id')).toBe('10');

    void first.source.emit('11', 'signData', SIGN_TEXT_PARAMS);
    await flush();
    expect(getSignDataUpdates(first.onUpdate)).toHaveLength(1);

    // The app stops before the user answers
    const second = await createAdapter();

    expect(second.source.url.searchParams.get('last_event_id')).toBe('10');
  });

  it('settles a request before its response is sent', async () => {
    const { source } = await createAdapter();
    let settledWhenSent: [string, number][] | undefined;
    mockFetch.mockImplementation(() => {
      settledWhenSent = mockStorage.state?.settled;
      return Promise.resolve({ ok: true, status: 200 });
    });

    const handling = source.emit('11', 'signData', SIGN_TEXT_PARAMS);
    await flush();
    mockDeferredRequests[0].resolve({ result: { signature: 'signature' } });
    await handling;

    expect(settledWhenSent?.map(([id]) => id)).toContain('11');
    expect(mockStorage.state?.cursor).toBe('11');
  });

  it('after a restart, shows the open request again but not the answered one delivered after it', async () => {
    const first = await createAdapter();
    void first.source.emit('11', 'signData', SIGN_TEXT_PARAMS);
    const answered = first.source.emit('12', 'signData', SIGN_TEXT_PARAMS);
    await flush();
    mockDeferredRequests[1].resolve({ result: { signature: 'signature' } });
    await answered;

    const second = await createAdapter();
    await second.source.emit('12', 'signData', SIGN_TEXT_PARAMS);
    void second.source.emit('11', 'signData', SIGN_TEXT_PARAMS);
    await flush();

    expect(getSignDataUpdates(second.onUpdate)).toHaveLength(1);
  });

  it('does not show an open request twice when a reconnect delivers it again', async () => {
    const { adapter, onUpdate, source } = await createAdapter();
    void source.emit('11', 'signData', SIGN_TEXT_PARAMS);
    await flush();

    await adapter.resetupRemoteConnection!();
    const reconnected = FakeEventSource.instances[FakeEventSource.instances.length - 1];
    void reconnected.emit('11', 'signData', SIGN_TEXT_PARAMS);
    await flush();

    expect(source.isClosed).toBe(true);
    expect(getSignDataUpdates(onUpdate)).toHaveLength(1);
  });

  it('leaves exactly one stream open after overlapping reconnects', async () => {
    const { adapter } = await createAdapter();

    await Promise.all([adapter.resetupRemoteConnection!(), adapter.resetupRemoteConnection!()]);

    expect(FakeEventSource.instances.filter(({ isClosed }) => !isClosed)).toHaveLength(1);
  });

  it('moves past an event from an unknown dapp', async () => {
    const { source } = await createAdapter();

    await source.emit('11', 'signData', SIGN_TEXT_PARAMS, otherDappKeys);
    await flush();

    expect(mockStorage.state?.cursor).toBe('11');
  });
});

describe('TonConnectAdapter deep link return URL', () => {
  const unknownClientId = toHex(otherDappKeys.publicKey);

  async function getDisconnectedUrl(ret: string) {
    const { adapter, onUpdate } = await createAdapter();
    await adapter.handleDeepLink(`tc://?v=2&id=${unknownClientId}&ret=${encodeURIComponent(ret)}`);

    const updates = onUpdate.mock.calls.filter(([update]) => update.type === 'dappDisconnected');
    expect(updates).toHaveLength(1);
    return updates[0][0].url;
  }

  beforeEach(() => {
    jest.clearAllMocks();
    FakeEventSource.instances = [];
    (globalThis as any).EventSource = FakeEventSource;
  });

  it.each([
    'javascript:alert(1)',
    'file:///etc/passwd',
    'data:text/html,hello',
    'vbscript:msgbox',
    'about:blank',
    'not a url',
  ])('opens no return URL for %s', async (ret) => {
    expect(await getDisconnectedUrl(ret)).toBeUndefined();
  });

  it.each([
    'https://example.com',
    'myapp://back',
  ])('keeps the return URL %s', async (ret) => {
    expect(await getDisconnectedUrl(ret)).toBe(ret);
  });
});
