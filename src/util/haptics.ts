import { Haptics, ImpactStyle } from '@capacitor/haptics';

import { IS_CAPACITOR, IS_TELEGRAM_APP } from '../config';
import { pause } from './schedulers';
import { getTelegramApp } from './telegram';

const VIBRATE_SUCCESS_END_PAUSE_MS = 1300;

export async function vibrate() {
  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.impactOccurred('soft');
  } else if (IS_CAPACITOR) {
    await Haptics.impact({ style: ImpactStyle.Light });
  }
}

export async function vibrateOnError() {
  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.notificationOccurred('error');
  } else if (IS_CAPACITOR) {
    await Haptics.impact({ style: ImpactStyle.Medium });
    await pause(100);
    await Haptics.impact({ style: ImpactStyle.Medium });
    await pause(75);
    await Haptics.impact({ style: ImpactStyle.Light });
  }
}

export async function vibrateOnSuccess(withPauseOnEnd = false) {
  if (!IS_CAPACITOR && !IS_TELEGRAM_APP) return;

  if (IS_TELEGRAM_APP) {
    getTelegramApp()?.HapticFeedback.notificationOccurred('success');
  } else {
    await Haptics.impact({ style: ImpactStyle.Light });
  }

  if (withPauseOnEnd) {
    await pause(VIBRATE_SUCCESS_END_PAUSE_MS);
  }
}
