import { Address, Cell } from '@ton/core';

import type { ApiNetwork, OnApiUpdate } from '../../../types';
import { ApiTransactionError } from '../../../types';

import { signDappData } from '../../../chains/ton/dapp';
import { resolveDappPromise } from '../../../common/dappPromises';
import { callHook } from '../../../hooks';
import { createTonConnectAdapter } from './index';
import { transformTonConnectMessageToUnified } from './utils';

const mockFetchStoredChainAccount = jest.fn();
const mockGetCurrentAccountId = jest.fn();
const mockGetDapp = jest.fn();
const mockFindLastConnectedAccount = jest.fn();
const mockSignData = jest.fn();

jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'), IS_EXTENSION: true, IS_AIR_APP: false,
}));
jest.mock('../../../../util/fetch', () => ({ fetchJsonWithProxy: jest.fn(), handleFetchErrors: jest.fn() }));
jest.mock('../../../chains/ton/wallet', () => ({
  getContractInfo: jest.fn(), getWalletPublicKey: jest.fn(), getWalletStateInit: jest.fn(),
}));
jest.mock('../../../common/accounts', () => ({
  fetchStoredChainAccount: (...args: unknown[]) => mockFetchStoredChainAccount(...args),
  getCurrentAccountId: () => mockGetCurrentAccountId(),
  getCurrentAccountIdOrFail: () => mockGetCurrentAccountId(),
  getCurrentNetwork: jest.fn(), waitLogin: jest.fn(),
}));
jest.mock('../../../methods/dapps', () => ({
  getDapp: (...args: unknown[]) => mockGetDapp(...args),
  findLastConnectedAccount: (...args: unknown[]) => mockFindLastConnectedAccount(...args),
}));
jest.mock('../../../methods', () => ({ createLocalTransactions: jest.fn() }));
jest.mock('../../../chains', () => ({ __esModule: true, default: {}, chains: {} }));
jest.mock('../../../chains/ton/transfer', () => ({ signTransfers: jest.fn() }));
jest.mock('../../../chains/ton/util/metadata', () => ({
  parsePayloadBase64: jest.fn(), preloadPayloadNfts: jest.fn(),
}));
jest.mock('../../../chains/ton/util/signer', () => ({
  getSigner: () => ({ signData: (...args: unknown[]) => mockSignData(...args) }),
}));
jest.mock('../../../common/mfa', () => ({ createMfaRequest: jest.fn() }));
jest.mock('../../../common/tokens', () => ({ getTokenBySlug: jest.fn() }));
jest.mock('../../../common/addresses', () => ({ getKnownAddressInfo: jest.fn() }));
jest.mock('../../../storages', () => ({}));
jest.mock('../../../common/helpers', () => ({ isUpdaterAlive: () => true }));
jest.mock('../../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('../../loadSignDataCellPreview', () => ({ loadSignDataCellPreview: jest.fn() }));
jest.mock('./analytics', () => ({
  ...jest.requireActual('./analytics'),
  recordTonConnectEvent: jest.fn(), finishTonConnectFlow: jest.fn(),
  setTonConnectFlowContext: jest.fn(), clearTonConnectFlowContext: jest.fn(),
}));

const URL = 'https://dapp.example';
const RAW_ADDRESS = `0:${'ab'.repeat(32)}`;
const OTHER_ADDRESS = `0:${'cd'.repeat(32)}`;
const payloads = [
  { type: 'text', text: 'Offline constraint test' },
  { type: 'binary', bytes: Buffer.from('test').toString('base64') },
  { type: 'cell', schema: 'empty$_ = Empty;', cell: Cell.EMPTY.toBoc().toString('base64') },
];

async function createFixture(network: ApiNetwork = 'mainnet') {
  const accountId = `0-${network}`;
  const address = Address.parseRaw(RAW_ADDRESS).toString({ bounceable: false });
  mockGetCurrentAccountId.mockResolvedValue(accountId);
  mockFindLastConnectedAccount.mockResolvedValue(accountId);
  mockFetchStoredChainAccount.mockResolvedValue({ type: 'ton', byChain: { ton: { address } } });
  mockGetDapp.mockResolvedValue({ url: URL, name: 'Test', chains: [{ chain: 'ton', network, address }] });
  const onUpdate = jest.fn<ReturnType<OnApiUpdate>, Parameters<OnApiUpdate>>((update) => {
    if (update.type === 'dappSignData') {
      void signDappData(update.accountId, URL, update.payloadToSign, 'synthetic-session')
        .then((result) => resolveDappPromise(update.promiseId, result));
    }
  });
  const adapter = createTonConnectAdapter();
  await adapter.init({
    onUpdate,
    env: {
      agentOverride: 'v1', isAgentV2Enabled: false, isSseSupported: false, byNetwork: { mainnet: {}, testnet: {} },
    },
    chainDappSupports: {},
  });
  return {
    onUpdate,
    sign: (payload: object) => adapter.signData(
      { url: URL },
      transformTonConnectMessageToUnified({
        id: 'request-1', method: 'signData', params: [JSON.stringify(payload)],
      }) as never,
    ),
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockSignData.mockResolvedValue(Buffer.alloc(64, 1));
});

it.each([
  { index: 0, network: 'mainnet', constraints: { network: '-3' }, error: ApiTransactionError.WrongNetwork },
  { index: 1, network: 'testnet', constraints: { network: '-239' }, error: ApiTransactionError.WrongNetwork },
  { index: 2, network: 'mainnet', constraints: { network: '-999' }, error: ApiTransactionError.WrongNetwork },
  { index: 0, network: 'mainnet', constraints: { network: '' }, error: ApiTransactionError.WrongNetwork },
  { index: 0, network: 'mainnet', constraints: { network: -239 }, error: ApiTransactionError.WrongNetwork },
  {
    index: 0, network: 'mainnet', constraints: { network: null }, // eslint-disable-line no-null/no-null
    error: ApiTransactionError.WrongNetwork,
  },
  { index: 1, network: 'mainnet', constraints: { from: OTHER_ADDRESS }, error: ApiTransactionError.WrongAddress },
  { index: 0, network: 'mainnet', constraints: { from: 'invalid-address' }, error: ApiTransactionError.WrongAddress },
  { index: 0, network: 'mainnet', constraints: { from: '' }, error: ApiTransactionError.WrongAddress },
  {
    index: 0, network: 'mainnet', constraints: { from: null }, // eslint-disable-line no-null/no-null
    error: ApiTransactionError.WrongAddress,
  },
  { index: 0, network: 'mainnet', constraints: { from: 123 }, error: ApiTransactionError.WrongAddress },
])('rejects $constraints on $network before approval or signing', async ({ index, network, constraints, error }) => {
  const { sign, onUpdate } = await createFixture(network as ApiNetwork);

  expect(await sign({ ...payloads[index], ...constraints })).toMatchObject({ success: false, error: { code: 1 } });

  expect(onUpdate).toHaveBeenCalledWith({ type: 'showError', error });
  expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'dappSignData' }));
  expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'dappLoading' }));
  expect(callHook).not.toHaveBeenCalled();
  expect(mockSignData).not.toHaveBeenCalled();
});

it.each([
  { index: 0, format: 'raw', from: RAW_ADDRESS },
  { index: 1, format: 'bounceable', from: Address.parseRaw(RAW_ADDRESS).toString({ bounceable: true }) },
  { index: 2, format: 'non-bounceable', from: Address.parseRaw(RAW_ADDRESS).toString({ bounceable: false }) },
])('accepts the same account in $format format and preserves the payload', async ({ index, from }) => {
  const { sign } = await createFixture();
  const request = Object.freeze({ ...payloads[index], from, network: '-239' });

  const result = await sign(request);

  expect(result).toMatchObject({ success: true, result: { result: { payload: request } } });
  expect(mockSignData).toHaveBeenCalledTimes(1);
  expect(mockSignData).toHaveBeenCalledWith(expect.any(Number), 'dapp.example', request);
});

it.each(['mainnet', 'testnet'] as const)('accepts omitted or matching network on %s', async (network) => {
  const { sign } = await createFixture(network);

  expect(await sign(payloads[0])).toMatchObject({ success: true });
  expect(await sign({ ...payloads[0], network: network === 'mainnet' ? '-239' : '-3' }))
    .toMatchObject({ success: true });

  expect(mockSignData).toHaveBeenCalledTimes(2);
});
