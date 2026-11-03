import { getActions } from '../../../global';

import { copyTextToClipboard } from '../../../util/clipboard';
import { getTranslation } from '../../../util/langProvider';

/**
 * Copies text from an Agent menu and says so in the wallet's toast once the clipboard holds it, as Telegram does after
 * copying a message and the wallet after copying an address
 */
export async function copyAgentText(text: string, toastKey: 'Message Copied' | 'Copied' = 'Message Copied') {
  await copyTextToClipboard(text);
  getActions().showToast({ message: getTranslation(toastKey), icon: 'icon-copy' });
}
