import type { Connector } from '../../util/PostMessageConnector';

async function injectWallet(isGram: boolean) {
  if (isGram) process.env.IS_GRAM_WALLET = '1';
  else delete process.env.IS_GRAM_WALLET;
  jest.resetModules();
  const { initTonConnect } = await import('./TonConnect');
  return initTonConnect({} as Connector);
}

afterEach(() => {
  delete (window as any).mytonwallet;
  delete (window as any).gramwallet;
  delete (window as any).tonwallet;
  delete process.env.IS_GRAM_WALLET;
});

it.each([true, false])('keeps coinstalled wallets separate when Gram loads first: %s', async (gramFirst) => {
  const first = await injectWallet(gramFirst);
  const second = await injectWallet(!gramFirst);

  expect(window.gramwallet.tonconnect).toBe(gramFirst ? first : second);
  expect(window.mytonwallet.tonconnect).toBe(gramFirst ? second : first);
  expect((window as any).tonwallet).toBe(window.gramwallet);
  expect(window.gramwallet.tonconnect).not.toBe(window.mytonwallet.tonconnect);
});

it('does not publish Gram aliases in a My Wallet build', async () => {
  const bridge = await injectWallet(false);

  expect(window.mytonwallet.tonconnect).toBe(bridge);
  expect((window as any).gramwallet).toBeUndefined();
  expect((window as any).tonwallet).toBeUndefined();
});
