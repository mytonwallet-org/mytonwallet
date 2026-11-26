import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig } from '../../types';
import { DappProtocolType } from '../../types';

import { fetchStoredChainAccount } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';
import { getDappByTopic } from './helpers';
import { createWalletConnectAdapter } from './index';

jest.mock('@reown/walletkit', () => ({}));
jest.mock('@walletconnect/core', () => ({}));
jest.mock('@walletconnect/utils', () => ({
  buildApprovedNamespaces: () => ({}),
  getSdkError: (key: string) => ({ code: 5000, message: key }),
}));
jest.mock('../../../../config', () => ({
  ...jest.requireActual('../../../../config'),
  WALLET_CONNECT_PROJECT_ID: '',
  IS_EXTENSION: false,
}));
jest.mock('../../../../util/logs', () => ({ logDebug: jest.fn(), logDebugError: jest.fn() }));
jest.mock('../../../../util/windowProvider/connector', () => ({}));
jest.mock('../../../chains', () => ({ __esModule: true, default: {} }));
jest.mock('../../../chains/evm/util/client', () => ({}));
jest.mock('../../../common/accounts', () => ({
  fetchStoredAccounts: jest.fn(),
  fetchStoredChainAccount: jest.fn(),
  getAccountIdByAddress: jest.fn(),
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
jest.mock('./evmTransaction', () => ({ resolveWalletConnectEvmSerializedTx: jest.fn() }));
jest.mock('./helpers', () => ({
  ...jest.requireActual('./helpers'),
  getDappByTopic: jest.fn(),
}));
jest.mock('./payMapping', () => ({}));

const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const TOPIC = 'topic';
const SERIALIZED_TX = '0x02c0';
const TX_PARAMS = { from: ADDRESS, to: '0x2222222222222222222222222222222222222222', value: '0x1' };
const BASE_MAINNET = 'eip155:8453';
const BASE_TESTNET = 'eip155:84532';
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: 'https://app.example',
  name: 'Example',
  iconUrl: '',
  connectedAt: 1,
  chains: [{ chain: 'base', network: 'mainnet', address: ADDRESS }],
};

const updates: ApiUpdate[] = [];
const respondSessionRequest = jest.fn();
const parseTransactionForPreview = jest.fn();

async function processRelayRequest(accountId: string, caip2: string, method: string, params: unknown) {
  jest.mocked(getDappByTopic).mockResolvedValue({ dapp, accountId } as never);

  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { base: { parseTransactionForPreview } },
  });
  (adapter as unknown as { walletKit: unknown }).walletKit = { respondSessionRequest, getActiveSessions: () => ({}) };

  await (adapter as unknown as { processSessionRequest(event: unknown): Promise<void> }).processSessionRequest({
    id: 9,
    topic: TOPIC,
    params: { chainId: caip2, request: { method, params } },
  });
}

function expectRefusalBeforeConfirmation() {
  expect(respondSessionRequest).toHaveBeenCalledTimes(1);
  expect(respondSessionRequest).toHaveBeenCalledWith({
    topic: TOPIC,
    response: { id: 9, jsonrpc: '2.0', error: expect.objectContaining({ message: expect.any(String) }) },
  });
  expect(resolveWalletConnectEvmSerializedTx).not.toHaveBeenCalled();
  expect(parseTransactionForPreview).not.toHaveBeenCalled();
  expect(createDappPromise).not.toHaveBeenCalled();
  expect(updates.map(({ type }) => type)).toEqual(['showError']);
}

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ byChain: { base: { address: ADDRESS } } } as never);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([{ chain: 'base', payload: { signature: '0xsignature', signedTx: '0xsigned' } }]),
  });
  respondSessionRequest.mockResolvedValue(undefined);
  jest.mocked(resolveWalletConnectEvmSerializedTx).mockResolvedValue(SERIALIZED_TX);
  parseTransactionForPreview.mockResolvedValue({ transfers: [{ chain: 'base', rawPayload: SERIALIZED_TX }] });
});

describe('relay EVM transaction on a session chain of another network than the account', () => {
  it.each([
    ['eth_sendTransaction', '2-mainnet', BASE_TESTNET, TX_PARAMS],
    ['eth_signTransaction', '2-mainnet', BASE_TESTNET, TX_PARAMS],
    ['eth_signTransaction', '2-mainnet', BASE_TESTNET, SERIALIZED_TX],
    ['eth_sendTransaction', '2-testnet', BASE_MAINNET, TX_PARAMS],
  ])('refuses %s for account %s on %s before any confirmation', async (method, accountId, caip2, transaction) => {
    await processRelayRequest(accountId, caip2, method, [transaction]);

    expectRefusalBeforeConfirmation();
  });

  it('refuses a Solana method that carries an EVM transaction before any confirmation', async () => {
    await processRelayRequest('2-mainnet', BASE_TESTNET, 'solana_signTransaction', { transaction: SERIALIZED_TX });

    expectRefusalBeforeConfirmation();
  });

  it.each([
    ['2-mainnet', BASE_MAINNET, 'mainnet'],
    ['2-testnet', BASE_TESTNET, 'testnet'],
  ])('opens the confirmation for account %s on %s', async (accountId, caip2, network) => {
    await processRelayRequest(accountId, caip2, 'eth_signTransaction', [TX_PARAMS]);

    expect(resolveWalletConnectEvmSerializedTx).toHaveBeenCalledWith(
      expect.objectContaining({ raw: TX_PARAMS, chain: 'base', network, caip2 }),
    );
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSendTransactions', operationChain: 'base' }));
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: '0xsignature' },
    });
  });
});

describe('relay EVM transaction passed as an array', () => {
  it('refuses the array before any confirmation', async () => {
    await processRelayRequest('2-mainnet', BASE_MAINNET, 'eth_signTransaction', [[SERIALIZED_TX]]);

    expectRefusalBeforeConfirmation();
  });
});
