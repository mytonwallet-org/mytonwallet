import { WalletKit } from '@reown/walletkit';
import type { Address, Blockhash } from '@solana/kit';
import {
  AccountRole,
  appendTransactionMessageInstructions,
  compileTransaction,
  createTransactionMessage,
  getAddressDecoder,
  getBase58Decoder,
  pipe,
  setTransactionMessageFeePayer,
  setTransactionMessageLifetimeUsingBlockhash,
} from '@solana/kit';

import type { ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig, DappSignDataRequest } from '../../types';
import { ApiCommonError } from '../../../types';
import { DappProtocolType } from '../../types';

import { getSignDataRefusal } from '../../../chains/solana/signData';
import { fetchStoredChainAccount } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { callHook } from '../../../hooks';
import { getDapp } from '../../../methods/dapps';
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
  IS_EXTENSION: true,
}));
jest.mock('../../../../util/logs', () => ({ logDebug: jest.fn(), logDebugError: jest.fn() }));
jest.mock('../../../../util/windowProvider/connector', () => ({}));
jest.mock('../../../chains', () => ({
  __esModule: true,
  default: { solana: { normalizeAddress: (address: string) => address } },
}));
jest.mock('../../../chains/evm/util/client', () => ({}));
jest.mock('../../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../../../common/dappPromises', () => ({ createDappPromise: jest.fn() }));
jest.mock('../../../common/helpers', () => ({}));
jest.mock('../../../hooks', () => ({ callHook: jest.fn() }));
jest.mock('../../../methods/dapps', () => ({ getDapp: jest.fn() }));
jest.mock('./evmTransaction', () => ({}));
jest.mock('./helpers', () => ({
  ...jest.requireActual('./helpers'),
  getDappByTopic: jest.fn(),
}));
jest.mock('./payMapping', () => ({}));

const ACCOUNT_ID = '2-mainnet';
const URL = 'https://app.example';
const TOPIC = 'topic';
const USER = makeAddress(1);
const ATTACKER = makeAddress(2);
const SYSTEM_PROGRAM = getAddressDecoder().decode(new Uint8Array(32));
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: URL,
  name: 'Example',
  iconUrl: '',
  connectedAt: 1,
  chains: [{ chain: 'solana', network: 'mainnet', address: USER }],
};

function makeAddress(seed: number) {
  return getAddressDecoder().decode(new Uint8Array(32).fill(seed));
}

function buildTransactionMessage(version: 'legacy' | 0) {
  const { messageBytes } = compileTransaction(pipe(
    createTransactionMessage({ version }),
    (tx) => setTransactionMessageFeePayer(USER, tx),
    (tx) => setTransactionMessageLifetimeUsingBlockhash(
      { blockhash: makeAddress(4) as string as Blockhash, lastValidBlockHeight: 1n },
      tx,
    ),
    (tx) => appendTransactionMessageInstructions([{
      programAddress: SYSTEM_PROGRAM as Address,
      accounts: [
        { address: USER, role: AccountRole.WRITABLE_SIGNER },
        { address: ATTACKER, role: AccountRole.WRITABLE },
      ],
      data: new Uint8Array([2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0]),
    }], tx),
  ));

  return getBase58Decoder().decode(messageBytes);
}

function buildInjectedRequest(data: string): DappSignDataRequest<DappProtocolType.WalletConnect> {
  return { id: '7', chain: 'solana', payload: { address: USER, data } };
}

function buildRelayEvent(message: string) {
  return {
    id: 9,
    topic: TOPIC,
    params: {
      chainId: 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
      request: { method: 'solana_signMessage', params: { message, pubkey: USER } },
    },
  };
}

const SIGN_IN_TEXT = getBase58Decoder().decode(new TextEncoder().encode('Sign in to app.example'));
const updates: ApiUpdate[] = [];
let deliverSessionRequest: ((event: ReturnType<typeof buildRelayEvent>) => Promise<void>) | undefined;
const walletKit = {
  on: jest.fn(),
  respondSessionRequest: jest.fn(),
  getActiveSessions: jest.fn(),
};

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { solana: { getSignDataRefusal } },
  });
  return adapter;
}

beforeAll(() => {
  if (typeof globalThis.indexedDB === 'undefined') {
    Object.defineProperty(globalThis, 'indexedDB', { value: {}, configurable: true });
  }
});

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  deliverSessionRequest = undefined;
  walletKit.on.mockImplementation((event: string, handler: typeof deliverSessionRequest) => {
    if (event === 'session_request') deliverSessionRequest = handler;
  });
  walletKit.getActiveSessions.mockReturnValue({});
  walletKit.respondSessionRequest.mockResolvedValue(undefined);
  jest.mocked(WalletKit.init).mockResolvedValue(walletKit as unknown as Awaited<ReturnType<typeof WalletKit.init>>);
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(getDappByTopic).mockResolvedValue({ dapp, accountId: ACCOUNT_ID } as never);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ byChain: { solana: { address: USER } } } as never);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve({ result: { signature: 'signature' } }),
  });
});

describe.each([
  ['legacy', 'legacy'],
  ['v0', 0],
] as const)('a %s transaction message sent as a Solana message', (_, version) => {
  it('is rejected for an injected dApp before the confirmation opens', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData(
      { url: URL, accountId: ACCOUNT_ID },
      buildInjectedRequest(buildTransactionMessage(version)),
    );

    expect(result).toMatchObject({ success: false, error: { code: -32602 } });
    expect(updates).toEqual([]);
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(callHook).not.toHaveBeenCalledWith('onWindowNeeded');
  });

  it('is answered with a JSON-RPC error over the relay before the confirmation opens', async () => {
    await createAdapter();

    await deliverSessionRequest!(buildRelayEvent(buildTransactionMessage(version)));

    expect(walletKit.respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(updates).toEqual([{ type: 'showError', error: ApiCommonError.Unexpected }]);
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(callHook).not.toHaveBeenCalledWith('onWindowNeeded');
  });
});

describe('a Solana message request without a message', () => {
  it('is answered with a JSON-RPC error over the relay before the confirmation opens', async () => {
    const event = buildRelayEvent(SIGN_IN_TEXT);
    await createAdapter();

    await deliverSessionRequest!({
      ...event,
      params: { ...event.params, request: { ...event.params.request, params: { pubkey: USER } as never } },
    });

    expect(walletKit.respondSessionRequest).toHaveBeenCalledTimes(1);
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', error: { code: -32602, message: expect.any(String) } },
    });
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(callHook).not.toHaveBeenCalledWith('onWindowNeeded');
  });
});

describe('a text sent as a Solana message', () => {
  it('opens the confirmation for an injected dApp', async () => {
    const adapter = await createAdapter();

    const result = await adapter.signData({ url: URL, accountId: ACCOUNT_ID }, buildInjectedRequest(SIGN_IN_TEXT));

    expect(result).toMatchObject({ success: true });
    expect(callHook).toHaveBeenCalledWith('onWindowNeeded');
    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappSignData',
      operationChain: 'solana',
      payloadToSign: { type: 'binary', bytes: SIGN_IN_TEXT },
    }));
  });

  it('opens the confirmation over the relay and returns the signature', async () => {
    await createAdapter();

    await deliverSessionRequest!(buildRelayEvent(SIGN_IN_TEXT));

    expect(callHook).toHaveBeenCalledWith('onWindowNeeded');
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSignData', operationChain: 'solana' }));
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: { signature: 'signature' } },
    });
  });
});
