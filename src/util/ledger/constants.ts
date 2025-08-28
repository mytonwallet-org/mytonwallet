export type PossibleWalletVersion = 'v3R2' | 'v4R2';

export enum LedgerWalletVersion {
  v3R2 = 'v3r2',
  v4R2 = 'v4',
}

export const INTERNAL_WORKCHAIN = 0; // workchain === -1 ? 255 : 0;
export const DEFAULT_WALLET_VERSION: PossibleWalletVersion = 'v4R2';

export const DEVICE_DETECT_ATTEMPTS = 3;
export const PAUSE = 125;
export const ATTEMPTS = 10;
export const IS_BOUNCEABLE = false;
