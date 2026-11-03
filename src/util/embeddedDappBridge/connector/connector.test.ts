import type { RegisterEvmInjectedWalletCb } from '../../injectedConnector/evmConnector';

import { initConnector } from './connector';

const CHANNEL = 'test-channel';
const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const TYPED_DATA = {
  domain: { name: 'Token', version: '1', chainId: 8453 },
  types: { Permit: [{ name: 'value', type: 'uint256' }] },
  primaryType: 'Permit',
  message: { value: '1' },
};

type OutMessage = { messageId: string; name: string; args: [{ chain?: string }] };

const RESPONSES: Record<string, unknown> = {
  'evmConnect:connect': {
    success: true,
    session: {
      chains: [
        { chain: 'ethereum', network: 'mainnet', address: ADDRESS },
        { chain: 'base', network: 'mainnet', address: ADDRESS },
      ],
    },
  },
  'evmConnect:signData': { success: true, result: { result: '0xsignature' } },
};

function initProvider() {
  const sent: OutMessage[] = [];
  const target = {
    postMessage: (data: OutMessage) => {
      sent.push(data);
      setTimeout(() => {
        window.dispatchEvent(new MessageEvent('message', {
          data: { channel: CHANNEL, messageId: data.messageId, type: 'methodResponse', response: RESPONSES[data.name] },
        }));
      });
    },
  } as unknown as Window;

  let provider: { request(args: { method: string; params?: unknown[] }): Promise<unknown> } | undefined;
  const registerEvm = ((wallet: { provider: typeof provider }) => {
    provider = wallet.provider;
  }) as unknown as RegisterEvmInjectedWalletCb;

  initConnector(
    'testBridge',
    CHANNEL,
    target,
    { deviceInfo: {} as never, protocolVersion: 2, isWalletBrowser: true },
    'Wallet',
    '<svg/>',
    jest.fn(),
    registerEvm,
  );

  return { provider: provider!, sent };
}

it('sends typed data with the chain the dApp switched to', async () => {
  const { provider, sent } = initProvider();

  await provider.request({ method: 'eth_requestAccounts' });
  await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: '0x2105' }] });
  await provider.request({ method: 'eth_signTypedData_v4', params: [ADDRESS, JSON.stringify(TYPED_DATA)] });

  expect(sent.filter(({ name }) => name === 'evmConnect:signData')).toEqual([
    expect.objectContaining({ args: [expect.objectContaining({ chain: 'base' })] }),
  ]);
});
