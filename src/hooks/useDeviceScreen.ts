import { MOBILE_SCREEN_MAX_WIDTH } from '../config';
import { useMediaQuery } from './useMediaQuery';

export const PORTRAIT_SCREEN_QUERY = `(max-width: ${MOBILE_SCREEN_MAX_WIDTH - 0.02}px)`;

let isPortrait: boolean | undefined;

export function useDeviceScreen() {
  isPortrait = useMediaQuery(PORTRAIT_SCREEN_QUERY);
  const isSmallHeight = useMediaQuery('(max-height: 43.5rem)');

  return {
    isPortrait: Boolean(isPortrait),
    isSmallHeight,
    isLandscape: !isPortrait,
    screenHeight: window.screen.height,
  };
}

export function getIsPortrait() {
  return isPortrait;
}

export function getIsLandscape() {
  return !isPortrait;
}
