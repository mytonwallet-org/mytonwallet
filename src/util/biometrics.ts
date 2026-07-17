import { IS_TELEGRAM_APP } from '../config';
import {
  getIsTelegramBiometricAuthSupported,
  getIsTelegramFaceIdAvailable,
  getIsTelegramTouchIdAvailable,
} from './telegram';
import { getIsMobileTelegramApp, IS_BIOMETRIC_AUTH_SUPPORTED } from './windowEnvironment';

export function getIsBiometricAuthSupported() {
  return IS_BIOMETRIC_AUTH_SUPPORTED || getIsNativeBiometricAuthSupported();
}

export function getIsNativeBiometricAuthSupported() {
  return IS_TELEGRAM_APP && getIsTelegramBiometricAuthSupported();
}

export function getIsFaceIdAvailable() {
  return IS_TELEGRAM_APP && getIsTelegramFaceIdAvailable();
}

export function getIsTouchIdAvailable() {
  return IS_TELEGRAM_APP && getIsTelegramTouchIdAvailable();
}

export function getDoesUsePinPad() {
  return getIsMobileTelegramApp();
}
