// The file is about sending data using the OS social sharing UI

import { getActions } from '../global';

import { copyTextToClipboard } from './clipboard';
import { getTranslation } from './langProvider';
import { IS_IOS, IS_TOUCH_ENV } from './windowEnvironment';

export async function shareUrl(url: string, title?: string) {
  if (await tryNavigatorShare({ url, title })) {
    return;
  }

  await copyTextToClipboard(url);
  getActions().showToast({
    message: getTranslation('Link Copied'),
    icon: 'icon-link',
  });
}

export async function shareFile(name: string, content: string, mimeType: string) {
  const file = new File([content], name, { type: mimeType });
  if (await tryNavigatorShare({ files: [file] })) {
    return;
  }

  const url = URL.createObjectURL(file);

  try {
    if (IS_IOS) {
      window.open(url, '_blank', 'noreferrer');
    } else {
      const link = document.createElement('a');
      link.href = url;
      link.download = name;
      link.click();
    }
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * Returns `true` if the sharing is successful. Returns `false` if the sharing is unsuccessful and another sharing
 * method should be tried. Throws in case of an unexpected error.
 */
async function tryNavigatorShare(data: ShareData) {
  if (!IS_TOUCH_ENV || !navigator.share) {
    return false;
  }

  try {
    await navigator.share(data);
    return true;
  } catch (error) {
    // Occurs when the user closes the sharing UI without choosing a sharing destination
    if (error instanceof Error && error.name === 'AbortError') {
      return true;
    }

    // Occurs when the sharing API is called not in response to a user gesture
    if (error instanceof Error && error.name === 'NotAllowedError') {
      return false;
    }

    throw error;
  }
}
