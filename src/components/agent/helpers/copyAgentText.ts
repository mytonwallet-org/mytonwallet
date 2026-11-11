import { getActions } from '../../../global';

import { copyTextToClipboard } from '../../../util/clipboard';
import { getTranslation } from '../../../util/langProvider';

// The strip `renderMarkdown` draws over a code block, which copies the code
const CODE_COPY_SELECTOR = '[data-agent-code-copy]';

/** Copies the code of the block whose strip, which `renderMarkdown` draws over the code, was clicked in an answer */
export function copyClickedAgentCode(e: React.MouseEvent) {
  if (!(e.target instanceof Element)) return;

  const code = e.target.closest(CODE_COPY_SELECTOR)?.nextElementSibling?.querySelector('code');
  if (!code) return;

  void copyAgentText(code.textContent ?? '', '$agent_copied');
}

/**
 * Copies text from an Agent menu and says so in the wallet's toast once the clipboard holds it, as Telegram does after
 * copying a message and the wallet after copying an address
 */
export async function copyAgentText(
  text: string,
  toastKey: '$agent_message_copied' | '$agent_copied' = '$agent_message_copied',
) {
  await copyTextToClipboard(text);
  getActions().showToast({ message: getTranslation(toastKey), icon: 'icon-copy' });
}
