import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig, DappSignDataRequest } from '../../types';
import type { WalletConnectEip712Params } from './types';
import { ApiCommonError } from '../../../types';
import { DappProtocolType } from '../../types';

import { fetchStoredAccounts, fetchStoredChainAccount, getAccountIdByAddress } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { getDapp } from '../../../methods/dapps';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';
import { getDappByTopic } from './helpers';
import { createWalletConnectAdapter } from './index';
import { buildPayAccounts } from './payMapping';

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
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: {
    ethereum: { normalizeAddress: (address: string) => address.toLowerCase() },
    base: { normalizeAddress: (address: string) => address.toLowerCase() },
  },
}));
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
jest.mock('./payMapping', () => ({
  buildPayAccounts: jest.fn(),
  buildPayMerchant: () => ({ name: 'Shop' }),
  parsePayOptionChain: () => 'base',
}));

const ACCOUNT_ID = '2-mainnet';
const URL = 'https://app.example';
const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const TOPIC = 'topic';
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: URL,
  name: 'Example',
  iconUrl: '',
  connectedAt: 1,
  chains: [{ chain: 'ethereum', network: 'mainnet', address: ADDRESS }],
};

function typedData(chainId: unknown): WalletConnectEip712Params {
  return {
    domain: {
      name: 'Token',
      version: '1',
      chainId,
      verifyingContract: '0x3333333333333333333333333333333333333333',
    },
    types: { Permit: [{ name: 'value', type: 'uint256' }] },
    primaryType: 'Permit',
    message: { value: '1' },
  };
}

function signMessage(chainId: unknown): DappSignDataRequest<DappProtocolType.WalletConnect> {
  return {
    id: '7',
    chain: 'ethereum',
    payload: { address: ADDRESS, eip712: typedData(chainId), isEthSign: true },
  };
}

function relayEvent(caip2: string, chainId: unknown) {
  return {
    id: 9,
    topic: TOPIC,
    params: {
      chainId: caip2,
      request: { method: 'eth_signTypedData_v4', params: [ADDRESS, JSON.stringify(typedData(chainId))] },
    },
  };
}

async function processRelayEvent(adapter: unknown, event: ReturnType<typeof relayEvent>) {
  await (adapter as { processSessionRequest(event: unknown): Promise<void> }).processSessionRequest(event);
}

const updates: ApiUpdate[] = [];
const respondSessionRequest = jest.fn();
const parseTransactionForPreview = jest.fn();

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { base: { parseTransactionForPreview } },
  });
  (adapter as unknown as { walletKit: unknown }).walletKit = { respondSessionRequest, getActiveSessions: () => ({}) };
  return adapter;
}

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(getDappByTopic).mockResolvedValue({ dapp, accountId: ACCOUNT_ID } as never);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    byChain: { ethereum: { address: ADDRESS }, base: { address: ADDRESS } },
  } as never);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve({ result: { signature: '0xsignature' } }),
  });
  respondSessionRequest.mockResolvedValue(undefined);
  jest.mocked(resolveWalletConnectEvmSerializedTx).mockResolvedValue('0x01');
  parseTransactionForPreview.mockResolvedValue({ transfers: [] });
});

describe('typed data for another chain', () => {
  it('rejects an injected request before the confirmation opens', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, signMessage(8453));

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('answers a relay request with a JSON-RPC error and shows it before any confirmation', async () => {
    const adapter = await createAdapter();

    await processRelayEvent(adapter, relayEvent('eip155:1', '0x2105'));

    expect(respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('opens the confirmation for typed data on the requested chain', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, signMessage('0x1'));

    expect(result).toMatchObject({ success: true });
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', operationChain: 'ethereum' }));
  });

  it('rejects a WalletConnect Pay request before its confirmation opens', async () => {
    const adapter = await createAdapter();
    (adapter as unknown as { activePayContext: unknown }).activePayContext = {
      accountId: ACCOUNT_ID,
      paymentId: 'payment',
      merchant: { name: 'Shop' },
    };
    const params = [ADDRESS, JSON.stringify(typedData(8453))];

    await expect(
      (adapter as unknown as {
        processPaySignData(chain: string, network: string, params: unknown, method: string): Promise<string>;
      }).processPaySignData('ethereum', 'mainnet', params, 'eth_signTypedData_v4'),
    ).rejects.toThrow();
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });
});

describe('typed data on a testnet session of a mainnet account', () => {
  const BASE_TESTNET_CAIP2 = 'eip155:84532';

  it('opens the confirmation for the session network and answers with the signature', async () => {
    const adapter = await createAdapter();

    await processRelayEvent(adapter, relayEvent(BASE_TESTNET_CAIP2, 84532));

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      operationChain: 'base',
      payloadToSign: expect.objectContaining({ type: 'eip712', network: 'testnet' }),
    }));
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: '0xsignature' },
    });
  });

  it('rejects the mainnet chain id', async () => {
    const adapter = await createAdapter();

    await processRelayEvent(adapter, relayEvent(BASE_TESTNET_CAIP2, 8453));

    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('does not take the network from an injected request', async () => {
    const adapter = await createAdapter();
    const message = signMessage(84532);
    message.chain = 'base';
    message.payload.network = 'testnet';

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message);

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(createDappPromise).not.toHaveBeenCalled();
  });
});

it('rejects mainnet typed data from a testnet relay account before its confirmation opens', async () => {
  const adapter = await createAdapter();
  jest.mocked(getDappByTopic).mockResolvedValue({ dapp, accountId: '2-testnet' } as never);

  await processRelayEvent(adapter, relayEvent('eip155:8453', 8453));

  expect(respondSessionRequest).toHaveBeenCalledWith({
    topic: TOPIC,
    response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
  });
  expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
  expect(createDappPromise).not.toHaveBeenCalled();
});

describe('WalletConnect Pay actions on another network than the account', () => {
  type PayAdapter = {
    activePayContext: unknown;
    processPayment(paymentLink: string, accountId: string): Promise<unknown>;
    showPayOptionSelection: jest.Mock;
    walletKit: { pay: unknown };
    signPayAction(action: unknown): Promise<string>;
    signPayActionsWithApprove(actions: unknown, operationChain: string): Promise<string[]>;
  };

  async function createPayAdapter() {
    const adapter = await createAdapter() as unknown as PayAdapter;
    adapter.activePayContext = { accountId: ACCOUNT_ID, paymentId: 'payment', merchant: { name: 'Shop' } };
    return adapter;
  }

  function signDataAction(caip2: string, chainId: unknown) {
    return {
      chainId: caip2,
      method: 'eth_signTypedData_v4',
      params: JSON.stringify([ADDRESS, JSON.stringify(typedData(chainId))]),
    };
  }

  it.each([84532, 8453])('rejects a Base Sepolia action for a mainnet account (domain chainId %p)', async (chainId) => {
    const adapter = await createPayAdapter();

    await expect(adapter.signPayAction(signDataAction('eip155:84532', chainId))).rejects.toThrow();
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects an approve on another network before its confirmation opens', async () => {
    const adapter = await createPayAdapter();
    const actions = [
      { walletRpc: signDataAction('eip155:8453', 8453) },
      { walletRpc: { chainId: 'eip155:84532', method: 'eth_sendTransaction', params: JSON.stringify([{}]) } },
    ];

    await expect(adapter.signPayActionsWithApprove(actions, 'base')).rejects.toThrow();
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects a later action on another network before any signing confirmation opens', async () => {
    const adapter = await createPayAdapter();
    const option = { id: 'option', account: `eip155:8453:${ADDRESS}` };
    const actions = [
      { walletRpc: signDataAction('eip155:8453', 8453) },
      { walletRpc: signDataAction('eip155:84532', 84532) },
    ];
    jest.mocked(buildPayAccounts).mockResolvedValue([option.account]);
    adapter.walletKit.pay = {
      getPaymentOptions: jest.fn().mockResolvedValue({ paymentId: 'payment', options: [option] }),
      getRequiredPaymentActions: jest.fn().mockResolvedValue(actions),
    };
    adapter.showPayOptionSelection = jest.fn().mockResolvedValue({ option, paymentId: 'payment' });

    await expect(adapter.processPayment('https://pay.example/payment', ACCOUNT_ID))
      .rejects.toThrow('Pay chain eip155:84532 is not on the account\'s network');

    expect(updates).not.toContainEqual(expect.objectContaining({ type: 'walletConnectPaySignData' }));
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('opens the confirmation for a mainnet action with a matching domain', async () => {
    const adapter = await createPayAdapter();

    await expect(adapter.signPayAction(signDataAction('eip155:8453', 8453))).resolves.toBe('0xsignature');
    expect(updates).toContainEqual(expect.objectContaining({
      type: 'walletConnectPaySignData',
      operationChain: 'base',
      payloadToSign: expect.objectContaining({ network: 'mainnet' }),
    }));
  });
});

describe('injected typed data for a wallet on both networks', () => {
  const MAINNET_ACCOUNT = '0-mainnet';
  const TESTNET_ACCOUNT = '1-testnet';
  const accounts = {
    [MAINNET_ACCOUNT]: { type: 'bip39', byChain: { base: { address: ADDRESS } } },
    [TESTNET_ACCOUNT]: { type: 'bip39', byChain: { base: { address: ADDRESS } } },
  };

  function baseSignMessage(chainId: unknown): DappSignDataRequest<DappProtocolType.WalletConnect> {
    return { id: '7', chain: 'base', payload: { address: ADDRESS, eip712: typedData(chainId), isEthSign: true } };
  }

  beforeEach(() => {
    jest.mocked(fetchStoredAccounts).mockResolvedValue(accounts as never);
    // The first stored account holding the address, whatever its network
    jest.mocked(getAccountIdByAddress).mockImplementation((address, chain) => Promise.resolve(
      Object.entries(accounts).find(([, account]) => account.byChain[chain as 'base']?.address === address)![0],
    ));
    jest.mocked(getDapp).mockImplementation((accountId) => Promise.resolve(
      accountId === TESTNET_ACCOUNT ? dapp : undefined,
    ));
  });

  it('checks against the account connected to the dApp and opens its confirmation', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL }, baseSignMessage(84532));

    expect(result).toMatchObject({ success: true });
    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      accountId: TESTNET_ACCOUNT,
      operationChain: 'base',
      payloadToSign: expect.objectContaining({ network: 'testnet' }),
    }));
  });

  it('rejects the mainnet chain id', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL }, baseSignMessage(8453));

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(createDappPromise).not.toHaveBeenCalled();
  });
});
