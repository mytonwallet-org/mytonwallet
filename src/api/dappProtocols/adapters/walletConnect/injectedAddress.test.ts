import { Transaction } from 'ethers';

import type { ApiAccountAny, ApiUpdate } from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type { DappProtocolConfig, DappSignDataRequest, DappTransactionRequest } from '../../types';
import { DappProtocolType } from '../../types';

import { fetchStoredAccounts, fetchStoredChainAccount } from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { getDapp } from '../../../methods/dapps';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';
import { createWalletConnectAdapter } from './index';

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
  default: {
    ethereum: { normalizeAddress: jest.requireActual('../../../chains/evm/address').normalizeAddress },
    solana: { normalizeAddress: (address: string) => address },
  },
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
jest.mock('./evmTransaction', () => ({ resolveWalletConnectEvmSerializedTx: jest.fn() }));
jest.mock('./payMapping', () => ({}));

const ACTIVE_ACCOUNT = '2-mainnet';
const OTHER_ACCOUNT = '5-mainnet';
const URL = 'https://dapp.example';
const ADDRESSES: Record<string, { ethereum: string; solana: string }> = {
  [ACTIVE_ACCOUNT]: {
    ethereum: '0x11A43B91414B2c7083888D8f4E963988ddEe12A3',
    solana: 'ActiveWa11et1111111111111111111111111111111',
  },
  [OTHER_ACCOUNT]: {
    ethereum: '0x52908400098527886E0F7030069857D2E4169EE7',
    solana: 'AnotherWa11et111111111111111111111111111111',
  },
};
const FOREIGN_ADDRESSES = {
  ethereum: '0xde709f2102306220921060314715629080e2fb77',
  solana: 'Attacker11111111111111111111111111111111111',
};
const dapp: StoredDappConnection = {
  protocolType: DappProtocolType.WalletConnect,
  url: URL,
  name: 'Dapp',
  iconUrl: '',
  connectedAt: 1,
};

const RECONNECT = { success: false, error: { code: 0, message: 'Please reconnect your wallet from the dapp.' } };

type Chain = 'ethereum' | 'solana';

const updates: ApiUpdate[] = [];
const parseTransactionForPreview = jest.fn();
const sendSignedTransaction = jest.fn();

function buildStoredAccount(accountId: string) {
  const { ethereum, solana } = ADDRESSES[accountId];

  return {
    type: 'mnemonic',
    byChain: { ethereum: { address: ethereum }, solana: { address: solana } },
  } as unknown as ApiAccountAny;
}

function buildSendMessage(chain: Chain, address: string): DappTransactionRequest<DappProtocolType.WalletConnect> {
  return {
    id: '1',
    chain,
    payload: { address, data: chain === 'solana' ? 'raw-transaction' : '0x01', isSignOnly: false },
  };
}

function buildSignMessage(chain: Chain, address: string): DappSignDataRequest<DappProtocolType.WalletConnect> {
  return { id: '1', chain, payload: { address, data: 'message', isEthSign: chain === 'ethereum' } };
}

async function createAdapter() {
  const adapter = createWalletConnectAdapter();
  await adapter.init({
    onUpdate: (update) => updates.push(update),
    env: {} as DappProtocolConfig['env'],
    chainDappSupports: {
      ethereum: { parseTransactionForPreview, sendSignedTransaction },
      solana: { parseTransactionForPreview, sendSignedTransaction },
    },
  });
  return adapter;
}

beforeEach(() => {
  jest.resetAllMocks();
  updates.length = 0;
  jest.mocked(fetchStoredAccounts).mockResolvedValue({
    [ACTIVE_ACCOUNT]: buildStoredAccount(ACTIVE_ACCOUNT),
    [OTHER_ACCOUNT]: buildStoredAccount(OTHER_ACCOUNT),
  });
  jest.mocked(fetchStoredChainAccount).mockImplementation((accountId) => (
    Promise.resolve(buildStoredAccount(accountId) as Awaited<ReturnType<typeof fetchStoredChainAccount>>)
  ));
  jest.mocked(getDapp).mockResolvedValue(dapp);
  jest.mocked(createDappPromise).mockReturnValue({
    promiseId: 'confirmation',
    promise: Promise.resolve([{ payload: { signedTx: 'signed-transaction' } }]),
  });
  jest.mocked(resolveWalletConnectEvmSerializedTx).mockResolvedValue('0xserialized');
  parseTransactionForPreview.mockResolvedValue({ transfers: [] });
  sendSignedTransaction.mockResolvedValue('transaction-id');
});

describe('a transaction request with the account set by the transport', () => {
  it.each<{ chain: Chain; name: string; address: string }>([
    { chain: 'solana', name: 'an address outside the wallet', address: FOREIGN_ADDRESSES.solana },
    { chain: 'ethereum', name: 'an address outside the wallet', address: FOREIGN_ADDRESSES.ethereum },
    { chain: 'solana', name: 'the address of another account', address: ADDRESSES[OTHER_ACCOUNT].solana },
    { chain: 'ethereum', name: 'the address of another account', address: ADDRESSES[OTHER_ACCOUNT].ethereum },
  ])('is rejected on $chain when the page names $name', async ({ chain, address }) => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(
      { url: URL, accountId: ACTIVE_ACCOUNT },
      buildSendMessage(chain, address),
    );

    expect(result).toMatchObject({ success: false, error: expect.any(Object) });
    expect(parseTransactionForPreview).not.toHaveBeenCalled();
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(sendSignedTransaction).not.toHaveBeenCalled();
    expect(updates).toEqual([]);
  });

  it('is rejected when the page names no address', async () => {
    const adapter = await createAdapter();
    const message = buildSendMessage('solana', '');
    delete message.payload.address;

    const result = await adapter.sendTransaction({ url: URL, accountId: ACTIVE_ACCOUNT }, message);

    expect(result).toMatchObject({ success: false, error: expect.any(Object) });
    expect(parseTransactionForPreview).not.toHaveBeenCalled();
    expect(createDappPromise).not.toHaveBeenCalled();
  });

  it.each<{ chain: Chain; address: string }>([
    { chain: 'solana', address: ADDRESSES[ACTIVE_ACCOUNT].solana },
    { chain: 'ethereum', address: ADDRESSES[ACTIVE_ACCOUNT].ethereum.toLowerCase() },
  ])('is previewed on $chain for the stored address of the signing account', async ({ chain, address }) => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(
      { url: URL, accountId: ACTIVE_ACCOUNT },
      buildSendMessage(chain, address),
    );

    expect(result).toMatchObject({ success: true });
    expect(parseTransactionForPreview).toHaveBeenCalledTimes(1);
    expect(parseTransactionForPreview).toHaveBeenCalledWith(
      chain === 'solana' ? 'raw-transaction' : '0xserialized',
      ADDRESSES[ACTIVE_ACCOUNT][chain],
      'mainnet',
    );
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toMatchObject({
      accountId: ACTIVE_ACCOUNT,
    });
  });
});

describe('a request from a page with no connection to the account set by the transport', () => {
  it.each<{ chain: Chain }>([{ chain: 'solana' }, { chain: 'ethereum' }])(
    'gets the same answer on $chain whether or not the address is the account\'s own',
    async ({ chain }) => {
      jest.mocked(getDapp).mockResolvedValue(undefined);
      const adapter = await createAdapter();
      const request = { url: URL, accountId: ACTIVE_ACCOUNT };

      const answers = [
        await adapter.sendTransaction(request, buildSendMessage(chain, ADDRESSES[ACTIVE_ACCOUNT][chain])),
        await adapter.sendTransaction(request, buildSendMessage(chain, FOREIGN_ADDRESSES[chain])),
        await adapter.signData(request, buildSignMessage(chain, ADDRESSES[ACTIVE_ACCOUNT][chain])),
        await adapter.signData(request, buildSignMessage(chain, FOREIGN_ADDRESSES[chain])),
      ];

      expect(answers).toEqual([RECONNECT, RECONNECT, RECONNECT, RECONNECT]);
      expect(createDappPromise).not.toHaveBeenCalled();
      expect(updates).toEqual([]);
    },
  );

  it('gets the same answer when the account has no wallet on the requested chain', async () => {
    jest.mocked(getDapp).mockResolvedValue(undefined);
    jest.mocked(fetchStoredChainAccount).mockRejectedValue(new Error('solana wallet missing in account'));
    const adapter = await createAdapter();
    const request = { url: URL, accountId: ACTIVE_ACCOUNT };

    const answers = [
      await adapter.sendTransaction(request, buildSendMessage('solana', FOREIGN_ADDRESSES.solana)),
      await adapter.signData(request, buildSignMessage('solana', FOREIGN_ADDRESSES.solana)),
    ];

    expect(answers).toEqual([RECONNECT, RECONNECT]);
  });
});

describe.each<{ method: 'sendTransaction' | 'signData' }>([
  { method: 'sendTransaction' },
  { method: 'signData' },
])('the connection of an injected $method request', ({ method }) => {
  const request = { url: URL, accountId: ACTIVE_ACCOUNT };

  function send(adapter: Awaited<ReturnType<typeof createAdapter>>, address: string) {
    return method === 'sendTransaction'
      ? adapter.sendTransaction(request, buildSendMessage('solana', address))
      : adapter.signData(request, buildSignMessage('solana', address));
  }

  it.each<{ name: string; address: string }>([
    { name: 'the signing account', address: ADDRESSES[ACTIVE_ACCOUNT].solana },
    { name: 'another wallet', address: FOREIGN_ADDRESSES.solana },
  ])('is read once when the page names $name', async ({ address }) => {
    const adapter = await createAdapter();

    await send(adapter, address);

    expect(getDapp).toHaveBeenCalledTimes(1);
  });

  it('is checked before the account is read', async () => {
    jest.mocked(getDapp).mockResolvedValue(undefined);
    const adapter = await createAdapter();

    const result = await send(adapter, FOREIGN_ADDRESSES.solana);

    expect(result).toEqual(RECONNECT);
    expect(getDapp).toHaveBeenCalledTimes(1);
    expect(fetchStoredChainAccount).not.toHaveBeenCalled();
  });
});

describe('an EVM transaction request whose parameters name a sender', () => {
  beforeEach(() => {
    jest.mocked(resolveWalletConnectEvmSerializedTx).mockImplementation(
      jest.requireActual('./evmTransaction').resolveWalletConnectEvmSerializedTx,
    );
  });

  function buildMessage(from: string): DappTransactionRequest<DappProtocolType.WalletConnect> {
    const message = buildSendMessage('ethereum', ADDRESSES[ACTIVE_ACCOUNT].ethereum.toLowerCase());
    message.payload.data = { from, to: FOREIGN_ADDRESSES.ethereum, value: '0x1' };
    return message;
  }

  it('is rejected when the sender is not the wallet that signs', async () => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(
      { url: URL, accountId: ACTIVE_ACCOUNT },
      buildMessage(ADDRESSES[OTHER_ACCOUNT].ethereum.toLowerCase()),
    );

    expect(result).toMatchObject({ success: false, error: expect.any(Object) });
    expect(parseTransactionForPreview).not.toHaveBeenCalled();
    expect(createDappPromise).not.toHaveBeenCalled();
    expect(updates).toEqual([]);
  });

  it('is previewed when the sender is the wallet that signs', async () => {
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(
      { url: URL, accountId: ACTIVE_ACCOUNT },
      buildMessage(ADDRESSES[ACTIVE_ACCOUNT].ethereum.toLowerCase()),
    );

    expect(result).toMatchObject({ success: true });
    expect(parseTransactionForPreview).toHaveBeenCalledTimes(1);
    const [serialized, previewAddress] = parseTransactionForPreview.mock.calls[0];
    expect(Transaction.from(serialized).to?.toLowerCase()).toBe(FOREIGN_ADDRESSES.ethereum);
    expect(previewAddress).toBe(ADDRESSES[ACTIVE_ACCOUNT].ethereum);
  });
});

describe('a request from a page with no connection and no account set by the transport', () => {
  it.each<{ chain: Chain }>([{ chain: 'solana' }, { chain: 'ethereum' }])(
    'gets the same answer on $chain whether or not the address is in the wallet',
    async ({ chain }) => {
      jest.mocked(getDapp).mockResolvedValue(undefined);
      const adapter = await createAdapter();
      const request = { url: URL };
      const ownAddress = ADDRESSES[ACTIVE_ACCOUNT][chain];

      const answers = [
        await adapter.sendTransaction(request, buildSendMessage(chain, ownAddress)),
        await adapter.sendTransaction(request, buildSendMessage(chain, FOREIGN_ADDRESSES[chain])),
        await adapter.signData(request, buildSignMessage(chain, ownAddress)),
        await adapter.signData(request, buildSignMessage(chain, FOREIGN_ADDRESSES[chain])),
      ];

      expect(answers).toEqual([RECONNECT, RECONNECT, RECONNECT, RECONNECT]);
      expect(createDappPromise).not.toHaveBeenCalled();
      expect(updates).toEqual([]);
    },
  );
});

describe('a transaction request without an account set by the transport', () => {
  it('is previewed for the stored address of the account found by the page address', async () => {
    jest.mocked(getDapp).mockImplementation((accountId) => Promise.resolve(
      accountId === OTHER_ACCOUNT ? dapp : undefined,
    ));
    const adapter = await createAdapter();

    const result = await adapter.sendTransaction(
      { url: URL },
      buildSendMessage('ethereum', ADDRESSES[OTHER_ACCOUNT].ethereum.toLowerCase()),
    );

    expect(result).toMatchObject({ success: true });
    expect(parseTransactionForPreview)
      .toHaveBeenCalledWith('0xserialized', ADDRESSES[OTHER_ACCOUNT].ethereum, 'mainnet');
    expect(updates.find((update) => update.type === 'dappSendTransactions')).toMatchObject({
      accountId: OTHER_ACCOUNT,
    });
  });
});

describe('a sign data request with the account set by the transport', () => {
  it.each<{ chain: Chain }>([{ chain: 'solana' }, { chain: 'ethereum' }])(
    'is rejected on $chain when the page names the address of another account',
    async ({ chain }) => {
      const adapter = await createAdapter();

      const result = await adapter.signData(
        { url: URL, accountId: ACTIVE_ACCOUNT },
        buildSignMessage(chain, ADDRESSES[OTHER_ACCOUNT][chain]),
      );

      expect(result).toMatchObject({ success: false, error: expect.any(Object) });
      expect(createDappPromise).not.toHaveBeenCalled();
      expect(updates).toEqual([]);
    },
  );

  it('reaches the confirmation when the page names the address of the signing account', async () => {
    jest.mocked(createDappPromise).mockReturnValue({
      promiseId: 'confirmation',
      promise: Promise.resolve({ result: { signature: 'signature' } }),
    });
    const adapter = await createAdapter();

    const result = await adapter.signData(
      { url: URL, accountId: ACTIVE_ACCOUNT },
      buildSignMessage('solana', ADDRESSES[ACTIVE_ACCOUNT].solana),
    );

    expect(result).toMatchObject({ success: true });
    expect(updates.find((update) => update.type === 'dappSignData')).toMatchObject({ accountId: ACTIVE_ACCOUNT });
  });
});
