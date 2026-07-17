import { IS_EXTENSION, IS_TELEGRAM_APP } from '../../../config';
import { getTelegramApp } from '../../../util/telegram';
import { IS_ELECTRON, IS_OPERA, IS_WINDOWS, REM } from '../../../util/windowEnvironment';
import windowSize from '../../../util/windowSize';

import { ELECTRON_HEADER_HEIGHT_REM } from '../../electron/ElectronHeader';

const WINDOWS_OPERA_EXTENSION_EXTRA_HEIGHT = 30;

export function calcSafeAreaTop() {
  const { safeAreaTop } = windowSize.get();
  const { safeAreaInset, contentSafeAreaInset } = IS_TELEGRAM_APP ? getTelegramApp()! : {};

  const electronExt = IS_ELECTRON ? ELECTRON_HEADER_HEIGHT_REM * REM : 0;
  const operaWinExt = IS_OPERA && IS_WINDOWS && IS_EXTENSION ? WINDOWS_OPERA_EXTENSION_EXTRA_HEIGHT : 0;
  return IS_TELEGRAM_APP
    ? safeAreaInset!.top + contentSafeAreaInset!.top
    : safeAreaTop + electronExt + operaWinExt;
}
