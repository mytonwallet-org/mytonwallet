import { IS_TELEGRAM_APP } from '../config';
import { pause } from './schedulers';
import { getTelegramApp } from './telegram';

const BROWSER_VIBRATION_DURATION_MS = 10;
const VIBRATE_SUCCESS_END_PAUSE_MS = 1300;

export function vibrate(isBrowserEnabled = false) {
  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.impactOccurred('soft');
  } else if (isBrowserEnabled) {
    navigator.vibrate?.(BROWSER_VIBRATION_DURATION_MS);
  }
}

export function vibrateOnError() {
  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.notificationOccurred('error');
  }
}

export async function vibrateOnSuccess(withPauseOnEnd = false) {
  if (!IS_TELEGRAM_APP) return;

  getTelegramApp()?.HapticFeedback.notificationOccurred('success');

  if (withPauseOnEnd) {
    await pause(VIBRATE_SUCCESS_END_PAUSE_MS);
  }
}
