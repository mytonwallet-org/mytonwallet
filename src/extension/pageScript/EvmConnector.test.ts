import type { Connector } from '../../util/PostMessageConnector';

import { EvmConnect } from './EvmConnector';

const ADDRESS = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const TYPED_DATA = {
  domain: { name: 'Token', version: '1', chainId: 8453 },
  types: { Permit: [{ name: 'value', type: 'uint256' }] },
  primaryType: 'Permit',
  message: { value: '1' },
};

function createConnector() {
  const request = jest.fn(({ name }: { name: string; args: unknown[] }) => {
    switch (name) {
      case 'walletConnect_connect':
        return Promise.resolve({
          success: true,
          session: {
            chains: [
              { chain: 'ethereum', network: 'mainnet', address: ADDRESS },
              { chain: 'base', network: 'mainnet', address: ADDRESS },
            ],
          },
        });
      case 'walletConnect_signData':
        return Promise.resolve({ success: true, result: { result: '0xsignature' } });
      default:
        return Promise.reject(new Error(`Unexpected request ${name}`));
    }
  });

  return { request, connector: { request } as unknown as Connector };
}

function signDataRequests(request: jest.Mock) {
  return request.mock.calls
    .map(([call]) => call as { name: string; args: [{ chain: string }] })
    .filter(({ name }) => name === 'walletConnect_signData');
}

it('sends typed data with the chain the dApp switched to', async () => {
  const { request, connector } = createConnector();
  const { provider } = new EvmConnect(connector);

  await provider.request({ method: 'eth_requestAccounts' });
  await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: '0x2105' }] });
  await provider.request({ method: 'eth_signTypedData_v4', params: [ADDRESS, JSON.stringify(TYPED_DATA)] });

  expect(signDataRequests(request)).toEqual([
    expect.objectContaining({ args: [expect.objectContaining({ chain: 'base' })] }),
  ]);
});
