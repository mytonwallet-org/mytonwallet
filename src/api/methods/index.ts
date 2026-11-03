import '../../util/bigintPatch';

import { IS_PERPS_ENABLED } from '../../config';

export { destroy } from './init';
export * from './activities';
export * from './analytics';
export * from './auth';
export * from './wallet';
export * from './transfer';
export * from './nfts';
export * from './domains';
export {
  initPolling,
  pollAccountConfig,
} from './polling';
export * from './accounts';
export * from './tokens';
export {
  initDapps,
  getDapps,
  getDappsByUrl,
  deleteDapp,
  deleteAllDapps,
  signDappProof,
  signDappTransfers,
  signDappData,
} from './dapps';
export * from './other';
export * from './market';
export * from './prices';
export * from './preload';

export { captureInstallAttribution } from './attribution';

export { retryWebFirstLaunch } from './webFunnel';

/** Available even in stripped builds so clients can check before calling optional Perps methods. */
export function isPerpsSupported(): boolean {
  return IS_PERPS_ENABLED && process.env.NO_EXTRA_FEATURES !== '1';
}
