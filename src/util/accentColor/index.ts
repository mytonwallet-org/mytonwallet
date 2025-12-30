import { type ElementRef, useLayoutEffect } from '../../lib/teact/teact';
import { setExtraStyles, toggleExtraClass } from '../../lib/teact/teact-dom';

import type { ApiNft } from '../../api/types';
import type { AppTheme } from '../../global/types';

import { MAX_WORKERS, requestMediaWorker } from '../launchMediaWorkers';
import { logDebugError } from '../logs';
import { getCardNftImageUrl } from '../url';
import {
  ACCENT_BNW_INDEX,
  ACCENT_COLORS,
  ACCENT_GOLD_INDEX,
  ACCENT_RADIOACTIVE_INDEX,
  ACCENT_SILVER_INDEX,
  COLOR_COUNT,
  QUALITY,
} from './constants';

const HEX_80_PERCENT = 'CC';
const HEX_10_PERCENT = '1A';

export function useAccentColor(
  elementRefOrBody: ElementRef<HTMLElement> | 'body',
  appTheme: AppTheme,
  accentColorIndex: number | undefined,
) {
  const accentColor = accentColorIndex ? ACCENT_COLORS[appTheme][accentColorIndex] : undefined;

  useLayoutEffect(() => {
    const element = elementRefOrBody === 'body' ? document.body : elementRefOrBody.current;
    if (!element) return;

    setExtraStyles(element, {
      '--color-accent': accentColor || 'inherit',
      '--color-accent-10o': accentColor ? `${accentColor}${HEX_10_PERCENT}` : 'inherit',
      '--color-accent-button-background': accentColor || 'inherit',
      '--color-accent-button-background-hover': accentColor ? `${accentColor}${HEX_80_PERCENT}` : 'inherit',
      '--color-accent-button-text': accentColor === '#FFFFFF' ? '#000000' : 'inherit',
      '--color-accent-button-text-hover': accentColor === '#FFFFFF' ? '#000000' : 'inherit',
    });

    toggleExtraClass(document.documentElement, 'is-white-accent', accentColor === '#FFFFFF');
  }, [elementRefOrBody, accentColor]);
}

export async function getAccentColorIndexFromNft(nft: ApiNft) {
  const { mtwCardType, mtwCardBorderShineType } = nft.metadata;

  if (mtwCardBorderShineType === 'radioactive') {
    return ACCENT_RADIOACTIVE_INDEX;
  }
  if (mtwCardType === 'silver') {
    return ACCENT_SILVER_INDEX;
  }
  if (mtwCardType === 'gold') {
    return ACCENT_GOLD_INDEX;
  }
  if (mtwCardType === 'platinum' || mtwCardType === 'black') {
    return ACCENT_BNW_INDEX;
  }

  const src = getCardNftImageUrl(nft, 'webp');
  if (!src) return undefined;

  try {
    return await requestMediaWorker({
      name: 'offscreen-canvas:processNftImage',
      args: [src, QUALITY, COLOR_COUNT],
    }, Math.round(nft.index) % MAX_WORKERS);
  } catch (error) {
    logDebugError('getAccentColorIndexFromNft', error);
    return undefined;
  }
}
