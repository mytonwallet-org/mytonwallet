/**
 * EIP-6963: Multi Injected Provider Discovery
 * https://eips.ethereum.org/EIPS/eip-6963
 */

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

export interface EIP1193Provider {
  request: (args: { method: string; params?: readonly unknown[] | Record<string, unknown> }) => Promise<unknown>;
  on?: (event: string, handler: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, handler: (...args: unknown[]) => void) => void;
  isMyTonWallet?: boolean;
}

export interface EIP6963ProviderInfo {
  uuid: string;
  name: string;
  icon: string;
  rdns: string;
}

export interface EIP6963ProviderDetail {
  info: EIP6963ProviderInfo;
  provider: EIP1193Provider;
}

const EIP6963_ANNOUNCE_PROVIDER = 'eip6963:announceProvider';
const EIP6963_REQUEST_PROVIDER = 'eip6963:requestProvider';

export function registerEvmInjectedWallet(detail: EIP6963ProviderDetail) {
  const frozenDetail = Object.freeze({
    info: Object.freeze({ ...detail.info }),
    provider: detail.provider,
  });

  function announceProvider() {
    window.dispatchEvent(new CustomEvent(EIP6963_ANNOUNCE_PROVIDER, { detail: frozenDetail }));
  }

  announceProvider();

  window.addEventListener(EIP6963_REQUEST_PROVIDER, announceProvider);

  if (!window.ethereum) {
    window.ethereum = detail.provider;
  }

  const interval = setInterval(announceProvider, 1000);
  setTimeout(() => clearInterval(interval), 10_000);

  return frozenDetail;
}

export type RegisterEvmInjectedWalletCb = typeof registerEvmInjectedWallet;
