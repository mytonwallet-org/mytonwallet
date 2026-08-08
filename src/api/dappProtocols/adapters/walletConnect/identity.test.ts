import {
  resolveWalletConnectDappUrl,
  resolveWalletConnectMethodDappUrl,
} from './identity';

describe('WalletConnect dApp identity', () => {
  it('binds injected connections to the authenticated request origin', () => {
    expect(resolveWalletConnectDappUrl({
      requestUrl: 'https://attacker.example/path',
      metadataUrl: 'https://victim.example/login',
      transport: 'inAppBrowser',
    })).toBe('https://attacker.example');
  });

  it('keeps relay metadata as the remote WalletConnect identity', () => {
    expect(resolveWalletConnectDappUrl({
      requestUrl: 'https://wallet.example',
      metadataUrl: 'https://dapp.example/path',
      transport: 'relay',
    })).toBe('https://dapp.example/path');
  });

  it('requires an authenticated URL for injected connections', () => {
    expect(() => resolveWalletConnectDappUrl({
      metadataUrl: 'https://victim.example',
      transport: 'inAppBrowser',
    })).toThrow('Missing authenticated dApp URL');
  });

  it('uses the authenticated request origin for injected methods', () => {
    expect(resolveWalletConnectMethodDappUrl('https://attacker.example/swap'))
      .toBe('https://attacker.example');
  });

  it('rejects non-web injected origins', () => {
    expect(() => resolveWalletConnectMethodDappUrl('file:///tmp/dapp.html'))
      .toThrow('Invalid authenticated dApp URL');
  });
});
