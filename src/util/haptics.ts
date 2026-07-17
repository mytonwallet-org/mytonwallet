import { IS_TELEGRAM_APP } from '../config';
import { pause } from './schedulers';
import { getTelegramApp } from './telegram';

const VIBRATE_SUCCESS_END_PAUSE_MS = 1300;

export function vibrate() {
  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.impactOccurred('soft');
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
