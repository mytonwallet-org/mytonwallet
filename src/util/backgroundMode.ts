import { IS_TELEGRAM_APP } from '../config';
import { createSignal } from './signals';
import { getTelegramAppAsync } from './telegram';

const [getIsInBackgroundLocal, setIsInBackground] = createSignal(!document.hasFocus());
export const getIsInBackground = getIsInBackgroundLocal;

if (IS_TELEGRAM_APP) {
  void getTelegramAppAsync().then((telegramApp) => {
    // Without the Telegram script there is no WebApp to report the activity, so the window reports it instead
    if (!telegramApp) {
      listenToWindowFocus();
      return;
    }

    telegramApp.onEvent('activated', handleFocus);
    telegramApp.onEvent('deactivated', handleBlur);
    setIsInBackground(!telegramApp.isActive);
  });
} else {
  listenToWindowFocus();
}

function listenToWindowFocus() {
  window.addEventListener('blur', handleBlur);
  window.addEventListener('focus', handleFocus);
}

function handleBlur() {
  setIsInBackground(true);
}

function handleFocus() {
  setIsInBackground(false);
}
