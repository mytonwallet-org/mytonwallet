import { getIsMobileTelegramApp } from '../util/windowEnvironment';

const isQrScannerSupported = getIsMobileTelegramApp();

export default function useQrScannerSupport() {
  return isQrScannerSupported;
}
