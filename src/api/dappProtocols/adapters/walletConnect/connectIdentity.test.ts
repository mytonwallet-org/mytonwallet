import type { WalletKitTypes } from '@reown/walletkit';
import { WalletKit } from '@reown/walletkit';

import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection, StoredSessionChain } from '../../storage';
import type {
  DappConnectionRequest,
  DappProtocolConfig,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../types';
import { DappProtocolType } from '../../types';

import { fetchStoredChainAccount, getAccountIdByAddress, getCurrentAccountId } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { ApiUserRejectsError } from '../../../errors';
import { callHook } from '../../../hooks';
import { addDapp, getDapp, getDappsState } from '../../../methods/dapps';
import { createWalletConnectAdapter } from './index';
import { getAccountChains } from './namespaces';

jest.mock('@reown/walletkit', () => ({ WalletKit: { init: jest.fn() } }));
jest.mock('@walletconnect/core', () => ({ Core: jest.fn() }));
jest.mock('@walletconnect/utils', () => ({
  buildApprovedNamespaces: () => ({}),
  buildAuthObject: (_payload: unknown, signature: unknown, iss: string) => ({ signature, iss }),
  getSdkError: (key: string) => ({ code: 0, message: key }),
  populateAuthPayload: ({ authPayload }: { authPayload: unknown }) => authPayload,
}));
jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  WALLET_CONNECT_PROJECT_ID: 'test-project',
  IS_AIR_APP: false,
  IS_EXTENSION: true,
}));
jest.mock('../../../../util/logs', () => ({ logDebug: jest.fn(), logDebugError: jest.fn() }));
jest.mock('../../../../util/windowProvider/connector', () => ({}));
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: { ethereum: { normalizeAddress: (address: string) => address.toLowerCase() } },
}));
jest.mock('../../../chains/evm/util/client', () => ({}));
jest.mock('../../../common/accounts', () => ({
  fetchStoredAccounts: () => Promise.resolve({}),
  fetchStoredChainAccount: jest.fn(),
  getAccountIdByAddress: jest.fn(),
  getCurrentAccountId: jest.fn(),
}));
jest.mock('../../../common/dappPromises', () => ({ createDappPromise: jest.fn() }));
jest.mock('../../../common/helpers', () => ({}));
jest.mock('../../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('../../../methods/dapps', () => ({
  addDapp: jest.fn(),
  deleteDapp: jest.fn(),
  findLastConnectedAccount: jest.fn(),
  getDapp: jest.fn(),
  getDappsState: jest.fn(),
  updateDapp: jest.fn(),
}));
jest.mock('./evmTransaction', () => ({ resolveWalletConnectEvmSerializedTx: () => Promise.resolve('0x01') }));
jest.mock('./namespaces', () => ({
  ...jest.requireActual('./namespaces'),
  getAccountChains: jest.fn(),
}));
jest.mock('./payMapping', () => ({}));

type WalletKitEvent = 'session_proposal' | 'session_authenticate' | 'session_request';

const ACCOUNT = '2-mainnet';
const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const PAGE_ORIGIN = 'https://evil.example';
const METADATA_URL = 'https://app.uniswap.org/swap';
const SESSION_TOPIC = 'session-topic';
const PAIRING_TOPIC = 'pairing-topic';
const AUTH_TOPIC = 'auth-topic';
const metadata = { name: 'Uniswap', description: '', url: METADATA_URL, icons: [] };
const chains: StoredSessionChain[] = [{ chain: 'ethereum', network: 'mainnet', address: ADDRESS }];
const invalidVerifyContext = {
  verified: { origin: METADATA_URL, validation: 'INVALID', verifyUrl: '', isScam: false },
} as const;
const scamVerifyContext = {
  verified: { origin: METADATA_URL, validation: 'UNKNOWN', verifyUrl: '', isScam: true },
} as const;

const relayDapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: METADATA_URL,
  name: 'Uniswap',
  iconUrl: '',
  connectedAt: 1,
  chains,
  wcTopic: SESSION_TOPIC,
  wcPairingTopic: PAIRING_TOPIC,
  urlTrustStatus: 'invalid',
};
const authDapp: StoredDappConnection = { ...relayDapp, wcTopic: undefined, wcPairingTopic: AUTH_TOPIC };

const proposal = {
  id: 7,
  params: {
    id: 7,
    expiryTimestamp: 2_000_000_000,
    relays: [{ protocol: 'irn' }],
    pairingTopic: PAIRING_TOPIC,
    proposer: { publicKey: '', metadata },
    requiredNamespaces: {},
    optionalNamespaces: { eip155: { chains: ['eip155:1'], methods: [], events: [] } },
  },
  verifyContext: invalidVerifyContext,
} as unknown as WalletKitTypes.SessionProposal;

const sessionAuthenticate = {
  id: 8,
  topic: AUTH_TOPIC,
  params: {
    requester: { publicKey: '', metadata },
    authPayload: { chains: ['eip155:1'], domain: 'app.uniswap.org', nonce: '1', aud: METADATA_URL, type: 'caip122' },
    expiryTimestamp: 2_000_000_000,
  },
  verifyContext: scamVerifyContext,
} as unknown as WalletKitTypes.SessionAuthenticate;

function buildConnectMessage(
  transport: DappConnectionRequest['transport'],
  params: { url: string; pairingTopic: string; redirect?: { native: string } },
): DappConnectionRequest<DappProtocolType.WalletConnect> {
  return {
    protocolType: DappProtocolType.WalletConnect,
    transport,
    requestedChains: [{ chain: 'ethereum', network: 'mainnet' }],
    permissions: { isAddressRequired: true, isPasswordRequired: false },
    protocolData: {
      id: 1,
      params: {
        id: 1,
        expiryTimestamp: 2_000_000_000,
        relays: [{ protocol: 'irn' }],
        pairingTopic: params.pairingTopic,
        proposer: {
          publicKey: '',
          metadata: { ...metadata, url: params.url, ...(params.redirect && { redirect: params.redirect }) },
        },
        requiredNamespaces: {},
        optionalNamespaces: {},
      },
    },
  };
}

const pageRelayMessage = buildConnectMessage('relay', { url: 'https://app.uniswap.org', pairingTopic: '' });

const updates: ApiUpdate[] = [];
const walletKitHandlers: Partial<Record<WalletKitEvent, (payload: unknown) => Promise<void>>> = {};
const walletKit = {
  on: jest.fn(),
  off: jest.fn(),
  approveSession: jest.fn(),
  approveSessionAuthenticate: jest.fn(),
  formatAuthMessage: jest.fn(),
  getActiveSessions: jest.fn(),
  rejectSession: jest.fn(),
  rejectSessionAuthenticate: jest.fn(),
  respondSessionRequest: jest.fn(),
};
const parseTransactionForPreview = jest.fn();
const sendSignedTransaction = jest.fn();

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { ethereum: { parseTransactionForPreview, sendSignedTransaction } },
  });
  return adapter;
}

function userRejects() {
  const promise = Promise.reject(new ApiUserRejectsError());
  promise.catch(() => undefined);
  return { promiseId: 'confirmation', promise };
}

function confirms(result: unknown) {
  return { promiseId: 'confirmation', promise: Promise.resolve(result) };
}

beforeAll(() => {
  if (typeof globalThis.indexedDB === 'undefined') {
    Object.defineProperty(globalThis, 'indexedDB', { value: {}, configurable: true });
  }
});

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  walletKit.on.mockImplementation((event: WalletKitEvent, handler: (payload: unknown) => Promise<void>) => {
    walletKitHandlers[event] = handler;
  });
  walletKit.approveSession.mockResolvedValue({ topic: SESSION_TOPIC });
  walletKit.approveSessionAuthenticate.mockResolvedValue({ session: { topic: SESSION_TOPIC } });
  walletKit.formatAuthMessage.mockReturnValue('Sign in to Uniswap');
  walletKit.getActiveSessions.mockReturnValue({});
  jest.mocked(WalletKit.init).mockResolvedValue(walletKit as unknown as Awaited<ReturnType<typeof WalletKit.init>>);
  jest.mocked(getCurrentAccountId).mockResolvedValue(ACCOUNT);
  jest.mocked(getAccountIdByAddress).mockResolvedValue(ACCOUNT);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue(
    { byChain: { ethereum: { address: ADDRESS } } } as unknown as Awaited<ReturnType<typeof fetchStoredChainAccount>>,
  );
  jest.mocked(getDappsState).mockResolvedValue({
    [ACCOUNT]: { [METADATA_URL]: { [PAIRING_TOPIC]: relayDapp, [AUTH_TOPIC]: authDapp } },
  });
  jest.mocked(getAccountChains).mockResolvedValue(chains);
  jest.mocked(createDappPromise).mockReturnValue(confirms({ accountId: ACCOUNT }));
  parseTransactionForPreview.mockResolvedValue({ transfers: [] });
  sendSignedTransaction.mockResolvedValue('0xhash');
});

describe('connect', () => {
  it.each(['relay', 'sse', 'unknown'])(
    'refuses an unsupported %s transport passed to the public connect',
    async (transport) => {
      const adapter = await createAdapter();

      const result = await adapter.connect(
        { url: PAGE_ORIGIN, urlTrustStatus: 'verified', accountId: ACCOUNT },
        { ...pageRelayMessage, transport: transport as DappConnectionRequest['transport'] },
        1,
      );

      expect(result).toEqual({ success: false, error: { code: 0, message: 'Unsupported transport' } });
      expect(updates).toEqual([]);
      expect(createDappPromise).not.toHaveBeenCalled();
      expect(addDapp).not.toHaveBeenCalled();
      expect(walletKit.rejectSession).not.toHaveBeenCalled();
    },
  );

  it.each(['extension', 'inAppBrowser'] as const)(
    'binds an injected %s connect to the transport origin and trust status, without page pairing data',
    async (transport) => {
      const adapter = await createAdapter();
      const message = buildConnectMessage(transport, {
        url: 'https://app.uniswap.org',
        pairingTopic: PAIRING_TOPIC,
        redirect: { native: 'evil://return' },
      });

      const result = await adapter.connect(
        { url: `${PAGE_ORIGIN}/swap`, urlTrustStatus: 'verified', accountId: ACCOUNT },
        message,
        1,
      );

      const expectedDapp = expect.objectContaining({
        url: PAGE_ORIGIN,
        urlTrustStatus: 'verified',
        wcPairingTopic: undefined,
      });
      expect(result).toMatchObject({ success: true, session: { dapp: expectedDapp } });
      expect(updates).toContainEqual(expect.objectContaining({ type: 'dappConnect', dapp: expectedDapp }));
      expect(addDapp).toHaveBeenCalledWith(ACCOUNT, expectedDapp, 'jsbridge');
    },
  );

  it('keeps an injected connect from binding the return to dApp of a relay pairing', async () => {
    const adapter = await createAdapter();
    await adapter.connect(
      { url: PAGE_ORIGIN, urlTrustStatus: 'verified', accountId: ACCOUNT },
      buildConnectMessage('extension', {
        url: PAGE_ORIGIN,
        pairingTopic: 'other-pairing',
        redirect: { native: 'evil://return' },
      }),
      1,
    );
    updates.length = 0;

    await walletKitHandlers.session_proposal!(proposal);

    expect(updates).toContainEqual({
      type: 'dappRequestSettled',
      promiseId: 'confirmation',
      returnStrategy: 'none',
      error: undefined,
    });
  });

  it('connects a session proposal under its metadata URL with the Verify API trust status', async () => {
    await createAdapter();

    await walletKitHandlers.session_proposal!(proposal);

    const expectedDapp = expect.objectContaining({
      url: METADATA_URL,
      urlTrustStatus: 'invalid',
      wcPairingTopic: PAIRING_TOPIC,
    });
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappConnect', dapp: expectedDapp }));
    expect(addDapp).toHaveBeenCalledWith(ACCOUNT, expectedDapp, PAIRING_TOPIC);
    expect(walletKit.approveSession).toHaveBeenCalledWith(expect.objectContaining({ id: 7 }));
  });

  it('asks to connect a session authenticate requester under its metadata URL with the Verify API status', async () => {
    jest.mocked(createDappPromise).mockImplementation(userRejects);
    await createAdapter();

    await walletKitHandlers.session_authenticate!(sessionAuthenticate);

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappConnect',
      dapp: expect.objectContaining({ url: METADATA_URL, urlTrustStatus: 'dangerous' }),
    }));
    expect(walletKit.rejectSessionAuthenticate).toHaveBeenCalledWith(expect.objectContaining({ id: 8 }));
    expect(addDapp).not.toHaveBeenCalled();
  });

  it('signs a session authenticate request under the paired dApp after the connection', async () => {
    jest.mocked(createDappPromise)
      .mockReturnValueOnce(confirms({ accountId: ACCOUNT }))
      .mockReturnValueOnce(confirms({ result: { signature: '0xsig' } }));
    await createAdapter();

    await walletKitHandlers.session_authenticate!(sessionAuthenticate);

    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', dapp: authDapp }));
    expect(walletKit.approveSessionAuthenticate).toHaveBeenCalledWith({
      id: 8,
      auths: [{ signature: { t: 'eip191', s: '0xsig' }, iss: `eip155:1:${ADDRESS}` }],
    });
    expect(walletKit.respondSessionRequest).not.toHaveBeenCalled();
  });
});

it('requires the injected origin\'s stored connection before opening the popup or confirming signData', async () => {
  const adapter = await createAdapter();
  const request = { url: `${PAGE_ORIGIN}/swap` };
  const message: DappSignDataRequest<DappProtocolType.WalletConnect> = {
    id: '1',
    chain: 'ethereum',
    payload: { address: ADDRESS, data: '0x01', isEthSign: true },
  };
  jest.mocked(createDappPromise).mockReturnValue(confirms({ result: { signature: '0xsig' } }));
  jest.mocked(getDapp).mockImplementation((_accountId, url) => Promise.resolve(
    url === METADATA_URL ? relayDapp : undefined,
  ));

  const unconnectedResult = await adapter.signData(request, message);

  expect(unconnectedResult).toEqual({
    success: false,
    error: { code: 0, message: 'Please reconnect your wallet from the dapp.' },
  });
  expect(getAccountIdByAddress).toHaveBeenCalledWith(ADDRESS, 'ethereum');
  expect(getDapp).toHaveBeenCalledWith(ACCOUNT, PAGE_ORIGIN, 'jsbridge');
  expect(updates).toEqual([]);
  expect(createDappPromise).not.toHaveBeenCalled();
  expect(callHook).not.toHaveBeenCalledWith('onWindowNeeded');

  const dapp: StoredDappConnection = {
    ...relayDapp,
    url: PAGE_ORIGIN,
    wcTopic: undefined,
    wcPairingTopic: undefined,
  };
  jest.mocked(getDapp).mockImplementation((_accountId, url) => Promise.resolve(
    url === PAGE_ORIGIN ? dapp : undefined,
  ));

  const connectedResult = await adapter.signData(request, message);

  expect(connectedResult).toEqual({ success: true, result: { result: '0xsig', id: '1' } });
  expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', dapp, accountId: ACCOUNT }));
  expect(createDappPromise).toHaveBeenCalledTimes(1);
  expect(callHook).toHaveBeenCalledWith('onWindowNeeded');
  expect(callHook).toHaveBeenCalledTimes(1);
  expect(jest.mocked(callHook).mock.invocationCallOrder[0])
    .toBeLessThan(jest.mocked(createDappPromise).mock.invocationCallOrder[0]);
  expect(walletKit.respondSessionRequest).not.toHaveBeenCalled();
});

describe('requests on relay sessions', () => {
  const request = { url: PAGE_ORIGIN, urlTrustStatus: 'verified', accountId: ACCOUNT } as const;
  const transaction: DappTransactionRequest<DappProtocolType.WalletConnect> = {
    id: '1',
    chain: 'ethereum',
    payload: { topic: SESSION_TOPIC, data: { from: ADDRESS, to: ADDRESS, value: '0x1' } },
  };
  const signDataRequests: [string, DappSignDataRequest<DappProtocolType.WalletConnect>][] = [
    ['a session topic', { id: '1', chain: 'ethereum', payload: { topic: SESSION_TOPIC, data: '0x01' } }],
    ['a session authenticate pairing', {
      id: '1',
      chain: 'ethereum',
      payload: { topic: AUTH_TOPIC, isSessionAuthenticate: true, data: 'Sign in', isEthSign: true },
    }],
    ['a session authenticate flag', {
      id: '1',
      chain: 'ethereum',
      payload: { address: ADDRESS, isSessionAuthenticate: true, data: 'Sign in', isEthSign: true },
    }],
  ];

  it('refuses a public sendTransaction that names a relay session topic', async () => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(request, transaction);

    expect(result).toMatchObject({ success: false });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(walletKit.respondSessionRequest).not.toHaveBeenCalled();
  });

  it.each(signDataRequests)('refuses a public signData that names %s', async (_, message) => {
    const adapter = await createAdapter();

    const result = await adapter.signData(request, message);

    expect(result).toMatchObject({ success: false });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(walletKit.respondSessionRequest).not.toHaveBeenCalled();
  });

  it('confirms an eth_sendTransaction session request under the session dApp', async () => {
    jest.mocked(createDappPromise).mockReturnValue(confirms([{ payload: { signedTx: '0x02' } }]));
    await createAdapter();

    await walletKitHandlers.session_request!({
      id: 9,
      topic: SESSION_TOPIC,
      params: {
        chainId: 'eip155:1',
        request: { method: 'eth_sendTransaction', params: [{ from: ADDRESS, to: ADDRESS, value: '0x1' }] },
      },
    });

    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSendTransactions', dapp: relayDapp }));
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: SESSION_TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: '0xhash' },
    });
  });

  it('confirms a personal_sign session request under the session dApp', async () => {
    jest.mocked(createDappPromise).mockReturnValue(confirms({ result: { signature: '0xsig' } }));
    await createAdapter();

    await walletKitHandlers.session_request!({
      id: 10,
      topic: SESSION_TOPIC,
      params: { chainId: 'eip155:1', request: { method: 'personal_sign', params: ['0x01', ADDRESS] } },
    });

    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', dapp: relayDapp }));
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: SESSION_TOPIC,
      response: { id: 10, jsonrpc: '2.0', result: '0xsig' },
    });
  });
});
