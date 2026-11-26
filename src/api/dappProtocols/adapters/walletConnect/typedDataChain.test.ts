import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig, DappSignDataRequest } from '../../types';
import type { WalletConnectEip712Params } from './types';
import { ApiCommonError } from '../../../types';
import { DappProtocolType } from '../../types';

import * as typedDataMessage from '../../../chains/evm/typedDataMessage';
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
    solana: { normalizeAddress: (address: string) => address },
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

describe('typed data naming its primary type', () => {
  const permit = {
    permitted: { token: '0x5555555555555555555555555555555555555555', amount: '1000' },
    spender: '0x4444444444444444444444444444444444444444',
  };

  function permitTypedData(primaryType: string, message: Record<string, unknown>): WalletConnectEip712Params {
    return {
      ...typedData(1),
      types: {
        PermitTransferFrom: [{ name: 'permitted', type: 'TokenPermissions' }, { name: 'spender', type: 'address' }],
        TokenPermissions: [{ name: 'token', type: 'address' }, { name: 'amount', type: 'uint256' }],
      },
      primaryType,
      message,
    };
  }

  function buildPermitRequest(eip712: WalletConnectEip712Params): DappSignDataRequest<DappProtocolType.WalletConnect> {
    return { id: '7', chain: 'ethereum', payload: { address: ADDRESS, eip712, isEthSign: true } };
  }

  const shownAsNestedType = permitTypedData('TokenPermissions', { ...permit, token: ADDRESS, amount: '0' });

  it.each([
    ['a nested type', shownAsNestedType],
    ['the domain type', permitTypedData('EIP712Domain', permit)],
    ['a missing type', permitTypedData('Missing', permit)],
  ])('rejects an injected request shown as %s before the confirmation opens', async (_, eip712) => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, buildPermitRequest(eip712));

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('answers a relay request with a JSON-RPC error and shows it before any confirmation', async () => {
    const adapter = await createAdapter();
    const event = relayEvent('eip155:1', 1);
    event.params.request.params = [ADDRESS, JSON.stringify(shownAsNestedType)];

    await processRelayEvent(adapter, event);

    expect(respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('checks the message of a relay request once before its confirmation', async () => {
    const check = jest.spyOn(typedDataMessage, 'getSignedTypedData');
    const adapter = await createAdapter();
    const event = relayEvent('eip155:1', 1);
    event.params.request.params = [ADDRESS, JSON.stringify(permitTypedData('PermitTransferFrom', permit))];

    await processRelayEvent(adapter, event);
    const checkCount = check.mock.calls.length;
    check.mockRestore();

    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData' }));
    expect(checkCount).toBe(1);
  });

  it('rejects typed data for another chain without checking its message', async () => {
    const check = jest.spyOn(typedDataMessage, 'getSignedTypedData');
    const adapter = await createAdapter();
    const pay = adapter as unknown as {
      activePayContext: unknown;
      processPaySignData(chain: string, network: string, params: unknown, method: string): Promise<string>;
    };
    pay.activePayContext = { accountId: ACCOUNT_ID, paymentId: 'payment', merchant: { name: 'Shop' } };
    const payParams = [ADDRESS, JSON.stringify(typedData(8453))];

    const injected = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, signMessage(8453));
    await processRelayEvent(adapter, relayEvent('eip155:1', '0x2105'));
    const payment = await pay.processPaySignData('ethereum', 'mainnet', payParams, 'eth_signTypedData_v4')
      .catch((err: Error) => err.message);
    const checkCount = check.mock.calls.length;
    check.mockRestore();

    expect(injected).toMatchObject({ success: false, error: { code: -32602 } });
    expect(payment).toMatch(/does not match the requested chain/);
    expect(checkCount).toBe(0);
  });

  it('rejects a WalletConnect Pay action before its confirmation opens', async () => {
    const adapter = await createAdapter() as unknown as {
      activePayContext: unknown;
      processPayment(paymentLink: string, accountId: string): Promise<unknown>;
      showPayOptionSelection: jest.Mock;
      walletKit: { pay: unknown };
    };
    const option = { id: 'option', account: `eip155:8453:${ADDRESS}` };
    const eip712 = { ...shownAsNestedType, domain: typedData(8453).domain };
    const walletRpc = {
      chainId: 'eip155:8453',
      method: 'eth_signTypedData_v4',
      params: JSON.stringify([ADDRESS, JSON.stringify(eip712)]),
    };
    adapter.activePayContext = { accountId: ACCOUNT_ID, paymentId: 'payment', merchant: { name: 'Shop' } };
    jest.mocked(buildPayAccounts).mockResolvedValue([option.account]);
    adapter.walletKit.pay = {
      getPaymentOptions: jest.fn().mockResolvedValue({ paymentId: 'payment', options: [option] }),
      getRequiredPaymentActions: jest.fn().mockResolvedValue([{ walletRpc }]),
    };
    adapter.showPayOptionSelection = jest.fn().mockResolvedValue({ option, paymentId: 'payment' });

    await expect(adapter.processPayment('https://pay.example/payment', ACCOUNT_ID))
      .rejects.toThrow('Invalid typed data');
    expect(updates).not.toContainEqual(expect.objectContaining({ type: 'walletConnectPaySignData' }));
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('shows only the message fields that get signed', async () => {
    const adapter = await createAdapter();
    const eip712 = permitTypedData('PermitTransferFrom', {
      ...permit,
      permitted: { ...permit.permitted, note: 'unsigned' },
      token: ADDRESS,
    });

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, buildPermitRequest(eip712));

    expect(result).toMatchObject({ success: true });
    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      payloadToSign: expect.objectContaining({ primaryType: 'PermitTransferFrom', message: permit }),
    }));
  });

  it('shows the types with nothing but the names that were checked', async () => {
    const adapter = await createAdapter();
    const eip712 = permitTypedData('PermitTransferFrom', permit);
    const { types } = eip712;
    const notedFields = types.TokenPermissions.map((field) => ({ ...field, note: 'unchecked' }));
    eip712.types = { ...types, TokenPermissions: notedFields };

    await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, buildPermitRequest(eip712));

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      payloadToSign: expect.objectContaining({ types: { ...types, EIP712Domain: expect.any(Array) } }),
    }));
  });
});

describe('requests whose signature would authorize the smart account', () => {
  const USER_OPERATION_HASH = `0x${'ab'.repeat(32)}`;

  function personalSign(data: string): DappSignDataRequest<DappProtocolType.WalletConnect> {
    return { id: '7', chain: 'ethereum', payload: { address: ADDRESS, data, isEthSign: true } };
  }

  function relayMessageEvent(method: string, params: string[]) {
    return { id: 9, topic: TOPIC, params: { chainId: 'eip155:1', request: { method, params } } };
  }

  it('rejects an injected 32-byte message before the confirmation opens', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, personalSign(USER_OPERATION_HASH));

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it.each([
    ['personal_sign', [USER_OPERATION_HASH, ADDRESS]],
    ['eth_sign', [ADDRESS, USER_OPERATION_HASH]],
  ])('answers a relay %s of 32 bytes with a JSON-RPC error', async (method, params) => {
    const adapter = await createAdapter();

    await processRelayEvent(adapter, relayMessageEvent(method, params) as never);

    expect(respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects injected typed data whose verifying contract is the wallet address', async () => {
    const adapter = await createAdapter();
    const message = signMessage(1);
    message.payload.eip712!.domain.verifyingContract = `0x${ADDRESS.slice(2).toUpperCase()}`;

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message);

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it.each([
    ['personal_sign', [USER_OPERATION_HASH, ADDRESS]],
    ['eth_sign', [ADDRESS, USER_OPERATION_HASH]],
    [
      'eth_signTypedData_v4',
      [ADDRESS, JSON.stringify({ ...typedData(8453), domain: { chainId: 8453, verifyingContract: ADDRESS } })],
    ],
  ])('rejects a WalletConnect Pay payment with a later %s before any confirmation opens', async (method, params) => {
    const adapter = await createAdapter() as unknown as {
      activePayContext: unknown;
      processPayment(paymentLink: string, accountId: string): Promise<unknown>;
      showPayOptionSelection: jest.Mock;
      walletKit: { pay: unknown };
    };
    adapter.activePayContext = { accountId: ACCOUNT_ID, paymentId: 'payment', merchant: { name: 'Shop' } };
    const option = { id: 'option', account: `eip155:8453:${ADDRESS}` };
    const actions = [
      {
        walletRpc: {
          chainId: 'eip155:8453',
          method: 'eth_signTypedData_v4',
          params: JSON.stringify([ADDRESS, JSON.stringify(typedData(8453))]),
        },
      },
      { walletRpc: { chainId: 'eip155:8453', method, params: JSON.stringify(params) } },
    ];
    jest.mocked(buildPayAccounts).mockResolvedValue([option.account]);
    adapter.walletKit.pay = {
      getPaymentOptions: jest.fn().mockResolvedValue({ paymentId: 'payment', options: [option] }),
      getRequiredPaymentActions: jest.fn().mockResolvedValue(actions),
    };
    adapter.showPayOptionSelection = jest.fn().mockResolvedValue({ option, paymentId: 'payment' });

    await expect(adapter.processPayment('https://pay.example/payment', ACCOUNT_ID))
      .rejects.toThrow('A 32-byte message or typed data of the wallet address is not signed');

    expect(updates).not.toContainEqual(expect.objectContaining({ type: 'walletConnectPaySignData' }));
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects a 32-byte message of an EVM chain that carries no `isEthSign` flag', async () => {
    const adapter = await createAdapter();
    const message = personalSign(USER_OPERATION_HASH);
    delete message.payload.isEthSign;

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message);

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('leaves a 32-byte message of another signing scheme to its own chain', async () => {
    const adapter = await createAdapter();
    const message: DappSignDataRequest<DappProtocolType.WalletConnect> = {
      id: '7',
      chain: 'solana',
      payload: { address: ADDRESS, data: USER_OPERATION_HASH },
    };
    jest.mocked(fetchStoredChainAccount).mockResolvedValue({ byChain: { solana: { address: ADDRESS } } } as never);

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message);

    expect(result).toMatchObject({ success: true });
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', operationChain: 'solana' }));
  });

  it.each([
    ['a text message', '0x5369676e20696e'],
    ['33 bytes', `0x${'ab'.repeat(33)}`],
    ['32 hex digits passed as text', '0123456789abcdefABCDEF0123456789'],
  ])('opens the confirmation for %s', async (_title, data) => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, personalSign(data));

    expect(result).toMatchObject({ success: true });
    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      payloadToSign: { type: 'binary', bytes: data },
    }));
  });
});

describe('typed data domain normalization', () => {
  const declaredDomain = [
    { name: 'name', type: 'string' },
    { name: 'version', type: 'string' },
    { name: 'chainId', type: 'uint256' },
  ];
  const normalizedDomain = [...declaredDomain, { name: 'verifyingContract', type: 'address' }];

  function undeclaredContractTypedData() {
    const eip712 = typedData(1);
    eip712.types.EIP712Domain = declaredDomain;
    return eip712;
  }

  function expectedPayload() {
    const eip712 = undeclaredContractTypedData();
    return {
      ...eip712,
      type: 'eip712',
      network: 'mainnet',
      domain: { ...eip712.domain, chainId: '1' },
      types: { ...eip712.types, EIP712Domain: normalizedDomain },
    };
  }

  it('includes an undeclared verifyingContract in the relay confirmation domain', async () => {
    const adapter = await createAdapter();
    const eip712 = undeclaredContractTypedData();
    const event = relayEvent('eip155:1', 1);
    event.params.request.params[1] = JSON.stringify(eip712);

    await processRelayEvent(adapter, event);

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      payloadToSign: expectedPayload(),
    }));
  });

  it('includes an undeclared verifyingContract in the injected confirmation domain', async () => {
    const adapter = await createAdapter();
    const eip712 = undeclaredContractTypedData();
    const message = signMessage(1);
    message.payload.eip712 = eip712;

    await expect(adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message))
      .resolves.toMatchObject({ success: true });

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      payloadToSign: expectedPayload(),
    }));
  });

  // eslint-disable-next-line no-null/no-null -- Injected typed data arrives from an untrusted page
  it.each([null, { name: 'Token', unknownField: 'hidden' }, [], { name: '\udc00' }, { salt: '0xab' }])(
    'rejects an invalid injected domain %p before opening the popup or confirmation',
    async (domain) => {
      const adapter = await createAdapter();
      const openExtensionPopup = jest.spyOn(
        adapter as unknown as { openExtensionPopup(): Promise<void> },
        'openExtensionPopup',
      ).mockResolvedValue(undefined);
      const message = signMessage(1);
      message.payload.eip712!.domain = domain as unknown as Record<string, unknown>;

      const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, message);

      expect(result).toMatchObject({ success: false, error: { code: -32602, message: 'Invalid typed data' } });
      expect(openExtensionPopup).not.toHaveBeenCalled();
      expect(updates).toEqual([]);
      expect(createDappPromise).not.toHaveBeenCalled();
    },
  );

  it('marks a relay request with an unsupported domain key as failed', async () => {
    const adapter = await createAdapter();
    const eip712 = undeclaredContractTypedData();
    eip712.domain.unknownField = 'hidden';
    const event = relayEvent('eip155:1', 1);
    event.params.request.params[1] = JSON.stringify(eip712);

    await processRelayEvent(adapter, event);

    expect(respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: 'Invalid typed data' } },
    });
    expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  async function processPayTypedData(eip712: WalletConnectEip712Params) {
    const adapter = await createAdapter();
    (adapter as unknown as { activePayContext: unknown }).activePayContext = {
      accountId: ACCOUNT_ID,
      paymentId: 'payment',
      merchant: { name: 'Shop' },
    };
    return (adapter as unknown as {
      processPaySignData(chain: string, network: string, params: unknown, method: string): Promise<string>;
    }).processPaySignData('ethereum', 'mainnet', [ADDRESS, JSON.stringify(eip712)], 'eth_signTypedData_v4');
  }

  it('includes an undeclared verifyingContract in the WalletConnect Pay confirmation domain', async () => {
    const eip712 = undeclaredContractTypedData();

    await expect(processPayTypedData(eip712)).resolves.toBe('0xsignature');

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'walletConnectPaySignData',
      payloadToSign: expectedPayload(),
    }));
  });

  it('answers a relay request whose domain is a list with an error and opens no confirmation', async () => {
    const adapter = await createAdapter();
    const event = relayEvent('eip155:1', 1);
    event.params.request.params[1] = JSON.stringify({ ...typedData(1), domain: [] });

    await processRelayEvent(adapter, event);

    expect(respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: 'Invalid typed data' } },
    });
    expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects a WalletConnect Pay domain that is a list before the confirmation', async () => {
    const eip712 = { ...typedData(1), domain: [] as unknown as Record<string, unknown> };

    await expect(processPayTypedData(eip712)).rejects.toThrow('Invalid typed data');

    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it('rejects an unsupported WalletConnect Pay domain key before the confirmation', async () => {
    const eip712 = undeclaredContractTypedData();
    eip712.domain.unknownField = 'hidden';

    await expect(processPayTypedData(eip712)).rejects.toThrow('Invalid typed data');

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
