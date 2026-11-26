import {
  buildApprovedNamespaces, createEncodedRecap, createRecap, encodeRecap, mergeEncodedRecaps,
} from '@walletconnect/utils';

import type { ApiUpdate } from '../../../types';
import type { DappProtocolConfig } from '../../types';
import { ApiTransactionError } from '../../../types';
import { SOLANA_CHAIN_IDS } from './types';

import { fetchStoredAccounts, fetchStoredChainAccount, getCurrentAccountId } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { addDapp, getDappsState } from '../../../methods/dapps';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';
import { createWalletConnectAdapter } from './index';

jest.mock('@reown/walletkit', () => ({}));
jest.mock('@walletconnect/core', () => ({}));
jest.mock('@walletconnect/utils', () => {
  const actual = jest.requireActual('@walletconnect/utils');

  return {
    buildApprovedNamespaces: jest.fn(),
    createEncodedRecap: actual.createEncodedRecap,
    createRecap: actual.createRecap,
    encodeRecap: actual.encodeRecap,
    getChainsFromRecap: actual.getChainsFromRecap,
    getRecapFromResources: actual.getRecapFromResources,
    getSdkError: (key: string) => ({ code: 5000, message: key }),
    mergeEncodedRecaps: actual.mergeEncodedRecaps,
    populateAuthPayload: actual.populateAuthPayload,
  };
});
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
  deleteDapp: jest.fn(),
  findLastConnectedAccount: jest.fn(),
  getDapp: jest.fn(),
  getDappsState: jest.fn(),
  updateDapp: jest.fn(),
}));
jest.mock('./evmTransaction', () => ({ resolveWalletConnectEvmSerializedTx: jest.fn() }));
jest.mock('./payMapping', () => ({}));

const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const DAPP_URL = 'https://app.example';
const PAIRING_TOPIC = 'pairing-topic';
const SESSION_TOPIC = 'session-topic';
const AUTH_TOPIC = 'auth-topic';
const SERIALIZED_TX = '0x02c0';
const TX_PARAMS = { from: ADDRESS, to: '0x2222222222222222222222222222222222222222', value: '0x1' };
const BASE_MAINNET = 'eip155:8453';
const BASE_TESTNET = 'eip155:84532';
const UNKNOWN_CHAIN = 'eip155:324';
const SOLANA_ADDRESS = '7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV';
const metadata = { name: 'Example', description: '', url: DAPP_URL, icons: [] };

type Namespaces = Record<string, { chains: string[]; methods: string[]; events: string[] }>;
type Adapter = {
  walletKit: unknown;
  handleSessionProposal(proposal: unknown): Promise<void>;
  handleSessionAuthenticate(payload: unknown): Promise<void>;
  processSessionRequest(event: unknown): Promise<void>;
};

const updates: ApiUpdate[] = [];
const parseTransactionForPreview = jest.fn();
const walletKit = {
  approveSession: jest.fn(),
  getActiveSessions: jest.fn(),
  rejectSession: jest.fn(),
  rejectSessionAuthenticate: jest.fn(),
  respondSessionRequest: jest.fn(),
};

function eip155(chains: string[]): Namespaces {
  return { eip155: { chains, methods: ['eth_sendTransaction'], events: [] } };
}

function proposal(requiredNamespaces: Namespaces, optionalNamespaces: Namespaces) {
  return {
    id: 7,
    params: {
      id: 7,
      expiryTimestamp: 2_000_000_000,
      relays: [{ protocol: 'irn' }],
      pairingTopic: PAIRING_TOPIC,
      proposer: { publicKey: '', metadata },
      requiredNamespaces,
      optionalNamespaces,
    },
  };
}

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: { base: { parseTransactionForPreview } },
  });
  (adapter as unknown as Adapter).walletKit = walletKit;

  return adapter as unknown as Adapter;
}

function useAccount(accountId: string, confirmedAccountId = accountId) {
  jest.mocked(getCurrentAccountId).mockResolvedValue(accountId);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve({ accountId: confirmedAccountId }),
  });
}

function useSolanaAddress() {
  jest.mocked(fetchStoredChainAccount).mockResolvedValue(
    { byChain: { solana: { address: SOLANA_ADDRESS } } } as never,
  );
}

function expectRefusalBeforeTheUserIsAsked() {
  expect(walletKit.rejectSession).toHaveBeenCalledTimes(1);
  expect(walletKit.approveSession).not.toHaveBeenCalled();
  expect(createDappPromise).not.toHaveBeenCalled();
  expect(addDapp).not.toHaveBeenCalled();
  expect(updates.map(({ type }) => type)).not.toContain('dappConnect');
  expect(updates).toContainEqual({ type: 'showError', error: ApiTransactionError.WrongNetwork });
}

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  jest.mocked(buildApprovedNamespaces).mockImplementation(
    ({ supportedNamespaces }) => supportedNamespaces as ReturnType<typeof buildApprovedNamespaces>,
  );
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ byChain: { base: { address: ADDRESS } } } as never);
  walletKit.approveSession.mockResolvedValue({ topic: SESSION_TOPIC });
  walletKit.getActiveSessions.mockReturnValue({});
  jest.mocked(resolveWalletConnectEvmSerializedTx).mockResolvedValue(SERIALIZED_TX);
  parseTransactionForPreview.mockResolvedValue({ transfers: [{ chain: 'base', rawPayload: SERIALIZED_TX }] });
});

describe('relay session proposal that names chains of both networks', () => {
  it.each([
    ['2-mainnet', 'mainnet', BASE_MAINNET],
    ['2-testnet', 'testnet', BASE_TESTNET],
  ])('approves account %s for its %s chain only, and a transaction on it opens the confirmation', async (
    accountId, network, caip2,
  ) => {
    useAccount(accountId);
    const adapter = await createAdapter();

    await adapter.handleSessionProposal(proposal({}, eip155([BASE_MAINNET, BASE_TESTNET])));

    const sessionChains = [{ chain: 'base', network, address: ADDRESS }];
    expect(walletKit.approveSession).toHaveBeenCalledWith({
      id: 7,
      namespaces: { eip155: expect.objectContaining({ chains: [caip2], accounts: [`${caip2}:${ADDRESS}`] }) },
    });
    expect(addDapp).toHaveBeenCalledWith(
      accountId, expect.objectContaining({ chains: sessionChains }), PAIRING_TOPIC,
    );

    const dapp = { ...jest.mocked(addDapp).mock.calls[0][1], wcTopic: SESSION_TOPIC };
    jest.mocked(getDappsState).mockResolvedValue({ [accountId]: { [DAPP_URL]: { [PAIRING_TOPIC]: dapp } } });
    jest.mocked(createDappPromise).mockReturnValue({
      promiseId: 'confirmation',
      promise: Promise.resolve([{ chain: 'base', payload: { signature: '0xsignature', signedTx: '0xsigned' } }]),
    });

    await adapter.processSessionRequest({
      id: 9,
      topic: SESSION_TOPIC,
      params: { chainId: caip2, request: { method: 'eth_signTransaction', params: [TX_PARAMS] } },
    });

    expect(resolveWalletConnectEvmSerializedTx).toHaveBeenCalledWith(
      expect.objectContaining({ chain: 'base', network, caip2 }),
    );
    expect(updates).toContainEqual(expect.objectContaining({ type: 'dappSendTransactions', operationChain: 'base' }));
    expect(walletKit.respondSessionRequest).toHaveBeenCalledWith({
      topic: SESSION_TOPIC,
      response: { id: 9, jsonrpc: '2.0', result: '0xsignature' },
    });
  });
});

describe('relay session proposal without a chain the account can use', () => {
  it.each([
    ['names only a testnet chain', '2-mainnet', {}, eip155([BASE_TESTNET])],
    ['names only a mainnet chain', '2-testnet', {}, eip155([BASE_MAINNET])],
    ['requires a testnet chain', '2-mainnet', eip155([BASE_TESTNET]), eip155([BASE_MAINNET])],
    ['names only a chain the wallet does not know', '2-mainnet', {}, eip155([UNKNOWN_CHAIN])],
  ])('is refused before the user is asked when it %s for account %s', async (
    _name, accountId, requiredNamespaces, optionalNamespaces,
  ) => {
    useAccount(accountId);
    const adapter = await createAdapter();

    await adapter.handleSessionProposal(proposal(requiredNamespaces, optionalNamespaces));

    expectRefusalBeforeTheUserIsAsked();
  });
});

describe('relay session proposal that names a Solana chain', () => {
  it.each(Object.entries(SOLANA_CHAIN_IDS))('approves a mainnet account for %s', async (caip2, chainId) => {
    useAccount('2-mainnet');
    useSolanaAddress();
    const adapter = await createAdapter();

    await adapter.handleSessionProposal(proposal(
      { solana: { chains: [caip2], methods: ['solana_signTransaction'], events: [] } }, {},
    ));

    expect(walletKit.approveSession).toHaveBeenCalledWith({
      id: 7,
      namespaces: { solana: expect.objectContaining({ chains: [caip2], accounts: [`${caip2}:${SOLANA_ADDRESS}`] }) },
    });
    expect(addDapp).toHaveBeenCalledWith(
      '2-mainnet', expect.objectContaining({ chains: [{ ...chainId, address: SOLANA_ADDRESS }] }), PAIRING_TOPIC,
    );
  });
});

describe('relay session proposal confirmed for another account than the current one', () => {
  it('is refused when the user confirms an account of another network', async () => {
    useAccount('2-mainnet', '2-testnet');
    const adapter = await createAdapter();

    await adapter.handleSessionProposal(proposal({}, eip155([BASE_MAINNET])));

    expect(updates.map(({ type }) => type)).toContain('dappConnect');
    expect(walletKit.rejectSession).toHaveBeenCalledTimes(1);
    expect(walletKit.approveSession).not.toHaveBeenCalled();
    expect(addDapp).not.toHaveBeenCalled();
  });

  it('asks for the chains of the account it switches to when the current one lacks the chain', async () => {
    useAccount('1-mainnet');
    jest.mocked(fetchStoredChainAccount).mockImplementation((accountId) => Promise.resolve(
      { byChain: accountId === '1-mainnet' ? {} : { base: { address: ADDRESS } } } as never,
    ));
    jest.mocked(fetchStoredAccounts).mockResolvedValue({ '3-testnet': { type: 'bip39' } } as never);
    const adapter = await createAdapter();

    await adapter.handleSessionProposal(proposal({}, eip155([BASE_MAINNET, BASE_TESTNET])));

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappConnect',
      accountId: '3-testnet',
      dapp: expect.objectContaining({ chains: [{ chain: 'base', network: 'testnet', address: ADDRESS }] }),
    }));
  });
});

describe('relay session authenticate request', () => {
  const recap = createEncodedRecap('eip155', 'request', ['eth_sendTransaction', 'personal_sign']);

  function sessionAuthenticate(chains: string[], resources?: string[]) {
    return {
      id: 8,
      topic: AUTH_TOPIC,
      params: {
        requester: { publicKey: '', metadata },
        authPayload: {
          chains, domain: 'app.example', nonce: '1', aud: DAPP_URL, type: 'caip122', version: '1', iat: '', resources,
        },
        expiryTimestamp: 2_000_000_000,
      },
    };
  }

  it.each([
    ['with a recap', [recap]],
    ['without a recap', undefined],
  ])('asks the user for the chains of the network of the account only, %s', async (_name, resources) => {
    useAccount('2-mainnet');
    const adapter = await createAdapter();

    await adapter.handleSessionAuthenticate(sessionAuthenticate([BASE_MAINNET, BASE_TESTNET], resources));

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappConnect',
      dapp: expect.objectContaining({ chains: [{ chain: 'base', network: 'mainnet', address: ADDRESS }] }),
    }));
  });

  const recapWithTestnetResource = mergeEncodedRecaps(recap, encodeRecap(
    createRecap('https://other.example', 'request', ['eth_sendTransaction'], { chains: [BASE_TESTNET] }),
  ));

  it.each(Object.entries(SOLANA_CHAIN_IDS))('asks the user when it names the Solana chain %s', async (
    caip2, chainId,
  ) => {
    useAccount('2-mainnet');
    useSolanaAddress();
    const adapter = await createAdapter();

    await adapter.handleSessionAuthenticate(sessionAuthenticate([caip2]));

    expect(updates).toContainEqual(expect.objectContaining({
      type: 'dappConnect',
      dapp: expect.objectContaining({ chains: [{ ...chainId, address: SOLANA_ADDRESS }] }),
    }));
  });

  it.each([
    ['only chains of another network, with a recap', [BASE_TESTNET], [recap]],
    ['only chains of another network, without a recap', [BASE_TESTNET], undefined],
    ['only a chain the wallet does not know', [UNKNOWN_CHAIN], [recap]],
    ['a chain of another network in a second resource of its recap', [BASE_MAINNET], [recapWithTestnetResource]],
  ])('is refused before the user is asked when it names %s', async (_name, chains, resources) => {
    useAccount('2-mainnet');
    const adapter = await createAdapter();

    await adapter.handleSessionAuthenticate(sessionAuthenticate(chains, resources));

    expect(walletKit.rejectSessionAuthenticate).toHaveBeenCalledTimes(1);
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(updates).toEqual([{ type: 'showError', error: ApiTransactionError.WrongNetwork }]);
  });
});
