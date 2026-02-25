// The file is about sending data using the OS social sharing UI

import { Directory, Encoding, Filesystem } from '@capacitor/filesystem';
import type { ShareOptions } from '@capacitor/share';
import { Share } from '@capacitor/share';
import { getActions } from '../global';

import { IS_CAPACITOR } from '../config';
import { copyTextToClipboard } from './clipboard';
import { getTranslation } from './langProvider';
import { IS_ANDROID, IS_ANDROID_APP, IS_IOS, IS_IOS_APP, IS_TOUCH_ENV } from './windowEnvironment';

export async function shareUrl(url: string, title?: string) {
  // Android Share supports only http/https/file URLs in `url` field.
  // For custom schemes (e.g., ton://), pass via `text` to ensure the chooser opens.
  const isShareableUrl = /^(https?:|file:)/.test(url);
  const shareData = IS_ANDROID && !isShareableUrl
    ? { text: url, title }
    : { url, title };

  if (await tryCapacitorShare(shareData) || await tryNavigatorShare({ url, title })) {
    return;
  }

  await copyTextToClipboard(url);
  getActions().showToast({
    message: getTranslation('Link Copied'),
    icon: 'icon-link',
  });
}

export async function shareFile(name: string, content: string, mimeType: string) {
  if (IS_CAPACITOR) {
    const fileLocation = {
      path: name,
      directory: Directory.Cache,
    };
    const file = await Filesystem.writeFile({
      ...fileLocation,
      data: content,
      encoding: Encoding.UTF8,
    });

    try {
      if (await tryCapacitorShare({ url: file.uri })) {
        return;
      }
    } finally {
      void Filesystem.deleteFile(fileLocation);
    }
  }

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
async function tryCapacitorShare(data: ShareOptions) {
  if (!IS_CAPACITOR) {
    return false;
  }

  try {
    await Share.share(data);
    return true;
  } catch (error) {
    // Occurs when the user closes the sharing UI without choosing a sharing destination
    if (error instanceof Error && error.message === 'Share canceled') {
      return true;
    }

    // Sometimes on iOS a false "Can't share while sharing is in progress" error is thrown
    if (error instanceof Error && error.message === 'Can\'t share while sharing is in progress') {
      return false;
    }

    throw error;
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

export function getShareIcon(): string {
  if (IS_IOS_APP) return 'icon-share-ios';
  if (IS_ANDROID_APP) return 'icon-share-android';
  return 'icon-link';
}
