import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappConnectionRequest, DappProtocolConfig, DappTransactionRequest } from '../../types';
import { DappProtocolType } from '../../types';

import { getCurrentAccountId, getCurrentAccountIdOrFail } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { addDapp, findLastConnectedAccount, getDapp } from '../../../methods/dapps';
import { createWalletConnectAdapter } from './index';
import { getAccountChains } from './namespaces';

jest.mock('@reown/walletkit', () => ({}));
jest.mock('@walletconnect/core', () => ({}));
jest.mock('@walletconnect/utils', () => ({ buildApprovedNamespaces: () => ({}) }));
jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  WALLET_CONNECT_PROJECT_ID: '',
  IS_EXTENSION: false,
}));
jest.mock('../../../../util/logs', () => ({ logDebug: jest.fn(), logDebugError: jest.fn() }));
jest.mock('../../../../util/windowProvider/connector', () => ({}));
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: { ethereum: { normalizeAddress: (address: string) => address.toLowerCase() } },
}));
jest.mock('../../../chains/evm/util/client', () => ({}));
jest.mock('../../../common/accounts', () => ({
  getCurrentAccountId: jest.fn(),
  getCurrentAccountIdOrFail: jest.fn(),
}));
jest.mock('../../../common/dappPromises', () => ({ createDappPromise: jest.fn() }));
jest.mock('../../../common/helpers', () => ({}));
jest.mock('../../../hooks', () => ({}));
jest.mock('../../../methods/dapps', () => ({
  addDapp: jest.fn(),
  findLastConnectedAccount: jest.fn(),
  getDapp: jest.fn(),
  updateDapp: jest.fn(),
}));
jest.mock('./evmTransaction', () => ({ resolveWalletConnectEvmSerializedTx: () => Promise.resolve('0x01') }));
jest.mock('./namespaces', () => ({
  ...jest.requireActual('./namespaces'),
  getAccountChains: jest.fn(),
}));
jest.mock('./payMapping', () => ({}));

const CURRENT_ACCOUNT = '2-mainnet';
const PREVIOUS_ACCOUNT = '5-mainnet';
const URL = 'https://1inch.com';
const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: URL,
  name: '1inch',
  iconUrl: '',
  connectedAt: 1,
  chains: [{ chain: 'ethereum', network: 'mainnet', address: ADDRESS }],
};
const connectMessage: DappConnectionRequest<DappProtocolType.WalletConnect> = {
  protocolType: DappProtocolType.WalletConnect,
  transport: 'inAppBrowser',
  requestedChains: [{ chain: 'ethereum', network: 'mainnet' }],
  permissions: { isAddressRequired: true, isPasswordRequired: false },
  protocolData: {
    id: 1,
    params: {
      id: 1,
      expiryTimestamp: 2_000_000_000,
      relays: [{ protocol: 'irn' }],
      pairingTopic: '',
      proposer: { publicKey: '', metadata: { name: '1inch', description: '', url: URL, icons: [] } },
      requiredNamespaces: {},
      optionalNamespaces: {},
    },
  },
};
const sendMessage: DappTransactionRequest<DappProtocolType.WalletConnect> = {
  id: '1',
  chain: 'ethereum',
  payload: { address: ADDRESS, data: '0x01', isSignOnly: true },
};

const updates: ApiUpdate[] = [];
const parseTransactionForPreview = jest.fn();

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { ethereum: { parseTransactionForPreview } },
  });
  return adapter;
}

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  jest.mocked(getCurrentAccountId).mockResolvedValue(CURRENT_ACCOUNT);
  jest.mocked(getCurrentAccountIdOrFail).mockResolvedValue(CURRENT_ACCOUNT);
  jest.mocked(findLastConnectedAccount).mockResolvedValue(PREVIOUS_ACCOUNT);
  jest.mocked(getDapp).mockImplementation((accountId) => Promise.resolve(
    accountId === PREVIOUS_ACCOUNT ? dapp : undefined,
  ));
  jest.mocked(getAccountChains).mockResolvedValue(dapp.chains!);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve({ accountId: CURRENT_ACCOUNT }),
  });
  parseTransactionForPreview.mockResolvedValue({ transfers: [] });
});

it('asks to connect the requested wallet instead of silently reusing another wallet', async () => {
  // The SDK's current account may also lag behind the native browser request.
  jest.mocked(getCurrentAccountId).mockResolvedValue(PREVIOUS_ACCOUNT);
  const adapter = await createAdapter();

  const result = await adapter.connect({ url: URL, accountId: CURRENT_ACCOUNT }, connectMessage, 1);

  expect(result).toMatchObject({ success: true, session: { accountId: CURRENT_ACCOUNT } });
  expect(updates).toContainEqual(expect.objectContaining({ type: 'dappConnect', accountId: CURRENT_ACCOUNT }));
  expect(getDapp).toHaveBeenCalledWith(CURRENT_ACCOUNT, URL, 'jsbridge');
  expect(findLastConnectedAccount).not.toHaveBeenCalled();
  expect(addDapp).toHaveBeenCalledWith(CURRENT_ACCOUNT, expect.objectContaining({ url: URL }), 'jsbridge');
});

it('silently reuses the requested wallet’s own connection', async () => {
  jest.mocked(getCurrentAccountId).mockResolvedValue(PREVIOUS_ACCOUNT);
  jest.mocked(getDapp).mockImplementation((accountId) => Promise.resolve(
    accountId === CURRENT_ACCOUNT ? dapp : undefined,
  ));
  const adapter = await createAdapter();

  const result = await adapter.connect({ url: URL, accountId: CURRENT_ACCOUNT }, connectMessage, 1);

  expect(result).toMatchObject({ success: true, session: { accountId: CURRENT_ACCOUNT, dapp } });
  expect(updates).toEqual([]);
  expect(createDappPromise).not.toHaveBeenCalled();
});

it('preserves last-connected-wallet restoration when no account is specified', async () => {
  const adapter = await createAdapter();

  const result = await adapter.connect({ url: URL }, connectMessage, 1);

  expect(result).toMatchObject({ success: true, session: { accountId: PREVIOUS_ACCOUNT, dapp } });
  expect(updates).toEqual([]);
});

it('rejects a missing connection before opening a skeleton or emitting a malformed confirmation', async () => {
  const adapter = await createAdapter();

  const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, sendMessage);

  expect(result).toEqual({
    success: false,
    error: { code: 0, message: 'Please reconnect your wallet from the dapp.' },
  });
  expect(updates).toEqual([]);
  expect(parseTransactionForPreview).not.toHaveBeenCalled();
  expect(createDappPromise).not.toHaveBeenCalled();
});

it('includes the saved dapp in a valid transaction confirmation', async () => {
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([{ payload: { signedTx: '0x02' } }]),
  });
  const adapter = await createAdapter();

  await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, sendMessage);

  const confirmation = updates.find((update) => update.type === 'dappSendTransactions');
  expect(JSON.parse(JSON.stringify(confirmation))).toMatchObject({ accountId: CURRENT_ACCOUNT, dapp });
});
