import { IS_CAPACITOR } from '../config';
import useSyncEffect from './useSyncEffect';

import { getInAppBrowser } from '../components/ui/InAppBrowser';

export default function useHideBrowser(
  isOpen?: boolean,
  isCompact?: boolean,
) {
  useSyncEffect(() => {
    if (!IS_CAPACITOR || isCompact) return;

    const browser = getInAppBrowser();
    if (!browser) return;

    if (isOpen && browser) {
      void browser.hide();
    }
  }, [isCompact, isOpen]);
}
