import { IS_TELEGRAM_APP } from '../config';
import { vibrate } from './haptics';
import { getTelegramApp } from './telegram';

const textCopyEl = document.createElement('textarea');
textCopyEl.setAttribute('readonly', '');
textCopyEl.tabIndex = -1;
textCopyEl.className = 'visually-hidden';

export const copyTextToClipboard = (str: string): Promise<void> => {
  vibrate();

  return navigator.clipboard.writeText(str);
};

export async function readClipboardContent() {
  if (IS_TELEGRAM_APP) {
    const telegramApp = getTelegramApp();
    if (!telegramApp) {
      throw new Error('Telegram Mini-App is unavailable');
    }

    return new Promise((resolve: ({ text, type }: { text: string; type: string | undefined }) => void) => {
      telegramApp.readTextFromClipboard((text) => {
        vibrate();
        resolve({ text, type: 'text/plain' });
      });
    });
  } else {
    const text = await navigator.clipboard.readText();
    return { text, type: 'text/plain' };
  }
}
