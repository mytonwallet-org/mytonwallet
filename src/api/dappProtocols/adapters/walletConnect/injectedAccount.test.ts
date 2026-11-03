import type { ApiDappTransfer, ApiEmulationResult, ApiUpdate } from '../../../types';
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
const sendSignedTransaction = jest.fn();

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: {
      ethereum: { parseTransactionForPreview },
      solana: { parseTransactionForPreview, sendSignedTransaction },
    },
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

it.each([{ isSignOnly: false }, {}])('rejects a batch to send with %j', async (options) => {
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([
      { payload: { signedTx: 'first-signed-transaction' } },
      { payload: { signedTx: 'second-signed-transaction' } },
    ]),
  });
  const adapter = await createAdapter();

  const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, {
    ...sendMessage,
    chain: 'solana',
    payload: { address: ADDRESS, data: ['first-transaction', 'second-transaction'], ...options },
  });

  expect(result.success).toBe(false);
  expect(updates).toEqual([]);
  expect(parseTransactionForPreview).not.toHaveBeenCalled();
  expect(createDappPromise).not.toHaveBeenCalled();
  expect(sendSignedTransaction).not.toHaveBeenCalled();
});

it('sends a single Solana transaction and returns its broadcast result', async () => {
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([{ payload: { signedTx: 'signed-transaction' } }]),
  });
  sendSignedTransaction.mockResolvedValue('transaction-signature');
  const adapter = await createAdapter();

  const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, {
    ...sendMessage,
    chain: 'solana',
    payload: { address: ADDRESS, data: 'raw-transaction', isSignOnly: false },
  });

  expect(sendSignedTransaction).toHaveBeenCalledTimes(1);
  expect(sendSignedTransaction).toHaveBeenCalledWith('signed-transaction', 'mainnet');
  expect(result).toEqual({ success: true, result: { result: 'transaction-signature', id: '1' } });
});

describe('transaction previews', () => {
  const transfers: ApiDappTransfer[] = ['first-transaction', 'second-transaction'].map((rawPayload) => ({
    chain: 'solana',
    toAddress: '',
    amount: 0n,
    rawPayload,
    isDangerous: false,
    normalizedAddress: '',
    displayedToAddress: '',
    networkFee: 0n,
  }));
  const emulations: ApiEmulationResult[] = transfers.map((transfer, index) => ({
    networkFee: BigInt(index + 1) * 10n,
    realFee: BigInt(index + 1) * 10n + 1n,
    received: BigInt(index + 1),
    traceOutputs: [{
      hashes: new Set([transfer.rawPayload!]),
      sent: 0n,
      received: BigInt(index + 1),
      networkFee: BigInt(index + 1) * 10n,
      isSuccess: true,
      walletActions: [],
      realFee: BigInt(index + 1) * 10n + 1n,
      excess: 0n,
    }],
    activities: [{
      id: '',
      kind: 'transaction',
      timestamp: 0,
      fromAddress: ADDRESS,
      toAddress: `recipient-${index}`,
      amount: -BigInt(index + 1),
      slug: 'solana',
      isIncoming: false,
      normalizedAddress: '',
      fee: BigInt(index + 1) * 10n + 1n,
      status: 'completed',
    }],
  }));
  const batchMessage: DappTransactionRequest<DappProtocolType.WalletConnect> = {
    ...sendMessage,
    chain: 'solana',
    payload: { ...sendMessage.payload, data: transfers.map((transfer) => transfer.rawPayload!) },
  };

  beforeEach(() => {
    jest.mocked(getDapp).mockResolvedValue(dapp);
    jest.mocked(createDappPromise).mockImplementation(() => ({
      promiseId: 'confirmation',
      promise: Promise.resolve().then(() => {
        const confirmation = updates.find((update) => update.type === 'dappSendTransactions');
        return confirmation!.transactions.map((transfer) => ({
          payload: { signedTx: `signed:${transfer.rawPayload}` },
        }));
      }),
    }));
    parseTransactionForPreview
      .mockResolvedValueOnce({ transfers: [transfers[0]], emulation: emulations[0] })
      .mockResolvedValueOnce({ transfers: [transfers[1]], emulation: emulations[1] });
  });

  it('previews every batch transaction with unique activity ids and total fees', async () => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result).toEqual({
      success: true,
      result: {
        result: 'signed:first-transaction',
        results: ['signed:first-transaction', 'signed:second-transaction'],
        id: '1',
      },
    });
    expect(sendSignedTransaction).not.toHaveBeenCalled();
    const confirmation = updates.find((update) => update.type === 'dappSendTransactions');
    expect(confirmation).toMatchObject({
      transactions: transfers,
      shouldHideTransfers: true,
      emulation: {
        networkFee: 30n,
        realFee: 32n,
        received: 3n,
        traceOutputs: [...emulations[0].traceOutputs, ...emulations[1].traceOutputs],
        activities: emulations.map((emulation) => ({ ...emulation.activities[0], id: expect.any(String) })),
      },
    });
    expect(new Set(confirmation!.emulation!.activities.map((activity) => activity.id)).size).toBe(2);
    expect(parseTransactionForPreview).toHaveBeenNthCalledWith(1, transfers[0].rawPayload, ADDRESS, 'mainnet');
    expect(parseTransactionForPreview).toHaveBeenNthCalledWith(2, transfers[1].rawPayload, ADDRESS, 'mainnet');
  });

  it('discards partial batch emulation and marks only unpreviewed transfers dangerous', async () => {
    parseTransactionForPreview.mockReset()
      .mockResolvedValueOnce({ transfers: [transfers[0]], emulation: emulations[0] })
      .mockResolvedValueOnce({ transfers: [transfers[1]] });
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result.success).toBe(true);
    const confirmation = updates.find((update) => update.type === 'dappSendTransactions');
    expect(confirmation).toMatchObject({
      transactions: [transfers[0], { ...transfers[1], isDangerous: true }],
      emulation: undefined,
      shouldHideTransfers: true,
    });
  });

  it('signs each batch transaction once in order and preserves danger from any parsed transfer', async () => {
    parseTransactionForPreview.mockReset()
      .mockResolvedValueOnce({
        transfers: [transfers[0], { ...transfers[0], isDangerous: true }],
        emulation: emulations[0],
      })
      .mockResolvedValueOnce({ transfers: [transfers[1]], emulation: emulations[1] });
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result).toEqual({
      success: true,
      result: {
        id: batchMessage.id,
        result: 'signed:first-transaction',
        results: ['signed:first-transaction', 'signed:second-transaction'],
      },
    });
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toMatchObject({
      transactions: [{ ...transfers[0], isDangerous: true }, transfers[1]],
    });
  });

  it('keeps one dangerous transfer for an unpreviewed batch transaction with multiple transfers', async () => {
    parseTransactionForPreview.mockReset()
      .mockResolvedValueOnce({ transfers: [transfers[0], { ...transfers[0] }] })
      .mockResolvedValueOnce({ transfers: [transfers[1]], emulation: emulations[1] });
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result.success).toBe(true);
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toMatchObject({
      transactions: [{ ...transfers[0], isDangerous: true }, transfers[1]],
      emulation: undefined,
    });
  });

  it('rejects a batch when signing returns a different number of transactions', async () => {
    jest.mocked(createDappPromise).mockReturnValue({
      promiseId: 'confirmation',
      promise: Promise.resolve([transfers[0], transfers[0], transfers[1]].map((transfer) => ({
        payload: { signedTx: `signed:${transfer.rawPayload}` },
      }))),
    });
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result).toMatchObject({ success: false, error: expect.any(Object) });
    expect(result).not.toHaveProperty('result');
  });

  it('rejects an empty batch transaction preview before requesting signatures', async () => {
    parseTransactionForPreview.mockReset()
      .mockResolvedValueOnce({ transfers: [], emulation: emulations[0] })
      .mockResolvedValueOnce({ transfers: [transfers[1]], emulation: emulations[1] });
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, batchMessage);

    expect(result).toMatchObject({ success: false, error: expect.any(Object) });
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(updates.some((update) => update.type === 'dappSendTransactions')).toBe(false);
  });

  it.each([
    { name: 'one-transaction batch', data: [transfers[0].rawPayload!] },
    { name: 'single-transaction request', data: transfers[0].rawPayload! },
  ])('preserves the confirmation for a $name', async ({ data }) => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction({ url: URL, accountId: CURRENT_ACCOUNT }, {
      ...batchMessage,
      payload: { ...batchMessage.payload, data },
    });

    expect(result.success).toBe(true);
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toEqual({
      type: 'dappSendTransactions',
      promiseId: 'confirmation',
      accountId: CURRENT_ACCOUNT,
      dapp,
      operationChain: 'solana',
      transactions: [transfers[0]],
      emulation: emulations[0],
      validUntil: expect.any(Number),
      vestingAddress: undefined,
      shouldHideTransfers: true,
      isLegacyOutput: true,
    });
    expect(parseTransactionForPreview).toHaveBeenCalledTimes(1);
  });
});
