import { WalletKit } from '@reown/walletkit';
import { Transaction } from 'ethers';

import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig } from '../../types';
import { DappProtocolType } from '../../types';

import { fetchStoredChainAccount } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { getDappByTopic } from './helpers';
import { createWalletConnectAdapter } from './index';

jest.mock('@reown/walletkit', () => ({ WalletKit: { init: jest.fn() } }));
jest.mock('@walletconnect/core', () => ({ Core: jest.fn() }));
jest.mock('@walletconnect/utils', () => ({
  buildApprovedNamespaces: () => ({}),
  getSdkError: (key: string) => ({ code: 5000, message: key }),
}));
jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  WALLET_CONNECT_PROJECT_ID: 'test-project',
  IS_AIR_APP: false,
  IS_EXTENSION: false,
}));
jest.mock('../../../../util/logs', () => ({ logDebug: jest.fn(), logDebugError: jest.fn() }));
jest.mock('../../../../util/windowProvider/connector', () => ({}));
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: { ethereum: { normalizeAddress: jest.requireActual('../../../chains/evm/address').normalizeAddress } },
}));
jest.mock('../../../chains/evm/util/client', () => ({}));
jest.mock('../../../common/accounts', () => ({
  fetchStoredAccounts: jest.fn(),
  fetchStoredChainAccount: jest.fn(),
  getCurrentAccountId: jest.fn(),
  getCurrentAccountIdOrFail: jest.fn(),
}));
jest.mock('../../../common/dappPromises', () => ({ createDappPromise: jest.fn() }));
jest.mock('../../../common/helpers', () => ({}));
jest.mock('../../../hooks', () => ({}));
jest.mock('../../../methods/dapps', () => ({ getDapp: jest.fn() }));
jest.mock('./helpers', () => ({
  ...jest.requireActual('./helpers'),
  getDappByTopic: jest.fn(),
}));
jest.mock('./payMapping', () => ({}));

type Method = 'eth_sendTransaction' | 'eth_signTransaction';

const ACCOUNT_ID = '2-mainnet';
const ADDRESS = '0x11A43B91414B2c7083888D8f4E963988ddEe12A3';
const OTHER_ADDRESS = '0x52908400098527886E0F7030069857D2E4169EE7';
const RECIPIENT = '0x2222222222222222222222222222222222222222';
const TOPIC = 'topic';
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: 'https://app.example',
  name: 'Example',
  iconUrl: '',
  connectedAt: 1,
  chains: [{ chain: 'ethereum', network: 'mainnet', address: ADDRESS }],
};

const updates: ApiUpdate[] = [];
const walletKit = {
  on: jest.fn(),
  off: jest.fn(),
  getActiveSessions: jest.fn(),
  respondSessionRequest: jest.fn(),
};
const parseTransactionForPreview = jest.fn();
const sendSignedTransaction = jest.fn();
let handleSessionRequest: ((event: unknown) => Promise<void>) | undefined;

async function requestOverRelay(method: Method, from: string) {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { ethereum: { parseTransactionForPreview, sendSignedTransaction } },
  });

  await handleSessionRequest!({
    id: 9,
    topic: TOPIC,
    params: { chainId: 'eip155:1', request: { method, params: [{ from, to: RECIPIENT, value: '0x1' }] } },
  });
}

beforeAll(() => {
  if (typeof globalThis.indexedDB === 'undefined') {
    Object.defineProperty(globalThis, 'indexedDB', { value: {}, configurable: true });
  }
});

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  handleSessionRequest = undefined;
  walletKit.on.mockImplementation((event: string, handler: (payload: unknown) => Promise<void>) => {
    if (event === 'session_request') handleSessionRequest = handler;
  });
  walletKit.getActiveSessions.mockReturnValue({});
  walletKit.respondSessionRequest.mockResolvedValue(undefined);
  jest.mocked(WalletKit.init).mockResolvedValue(walletKit as unknown as Awaited<ReturnType<typeof WalletKit.init>>);
  jest.mocked(getDappByTopic).mockResolvedValue({ dapp, accountId: ACCOUNT_ID } as never);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ byChain: { ethereum: { address: ADDRESS } } } as never);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([{ payload: { signedTx: '0xsigned', signature: '0xsignature' } }]),
  });
  parseTransactionForPreview.mockResolvedValue({ transfers: [] });
  sendSignedTransaction.mockResolvedValue('0xhash');
});

describe.each<{ method: Method }>([
  { method: 'eth_sendTransaction' },
  { method: 'eth_signTransaction' },
])('a relay $method request', ({ method }) => {
  it('is rejected when its sender is not the wallet of the session', async () => {
    await requestOverRelay(method, OTHER_ADDRESS.toLowerCase());

    expect(parseTransactionForPreview).not.toHaveBeenCalled();
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(sendSignedTransaction).not.toHaveBeenCalled();
    expect(updates.some((update) => update.type === 'dappSendTransactions')).toBe(false);
    expect(walletKit.respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: 5000, message: 'USER_REJECTED' } },
    });
  });

  it('opens the confirmation when its sender is the wallet of the session', async () => {
    await requestOverRelay(method, ADDRESS.toLowerCase());

    expect(parseTransactionForPreview).toHaveBeenCalledTimes(1);
    const [serialized, previewAddress] = parseTransactionForPreview.mock.calls[0];
    expect(Transaction.from(serialized).to).toBe(RECIPIENT);
    expect(previewAddress).toBe(ADDRESS);
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toMatchObject({ accountId: ACCOUNT_ID });
    expect(walletKit.respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: expect.any(String) },
    });
  });
});
