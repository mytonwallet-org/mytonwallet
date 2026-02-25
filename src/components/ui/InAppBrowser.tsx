import type { InAppBrowserObject } from '@awesome-cordova-plugins/in-app-browser';
import { memo, useEffect, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';

import { ANIMATION_LEVEL_DEFAULT } from '../../config';
import { INAPP_BROWSER_OPTIONS } from '../../util/capacitor';
import { listenOnce } from '../../util/domEvents';
import { buildInAppBrowserBridgeConnectorCode } from '../../util/embeddedDappBridge/connector/inAppBrowserConnector';
import { useInAppBrowserBridgeProvider } from '../../util/embeddedDappBridge/provider/useInAppBrowserBridgeProvider';
import { compact } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { waitFor } from '../../util/schedulers';
import { convertExplorerUrl, getHostnameFromUrl } from '../../util/url';
import { IS_IOS, IS_IOS_APP } from '../../util/windowEnvironment';

import useExplorerUrl from '../../hooks/useExplorerUrl';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

type CustomInAppBrowserObject = Omit<InAppBrowserObject, 'hide' | 'close'> & {
  hide(): Promise<void>;
  close(): Promise<void>;
};

interface StateProps {
  title?: string;
  subtitle?: string;
  url?: string;
  theme: string;
  animationLevel?: number;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
  isTestnet?: boolean;
}

interface MenuItemSelectedEvent {
  type: 'menuitemselected';
  payload: {
    key: string;
    value: string;
  };
}

// The maximum time the in-app browser will take to close (and a little more as a safe margin)
const CLOSE_MAX_DURATION = 900;

// eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
let inAppBrowser: Cordova['InAppBrowser'] | undefined;

function InAppBrowser({
  title, subtitle, url, theme, animationLevel, selectedExplorerIds, isTestnet,
}: StateProps) {
  const { closeBrowser, setSelectedExplorerId } = getActions();

  const lang = useLang();

  const {
    currentUrl,
    currentExplorerId,
    explorers,
    explorerInfo,
  } = useExplorerUrl({
    url,
    selectedExplorerIds,
    isTestnet,
  });

  const { setupDappBridge, cleanupDappBridge } = useInAppBrowserBridgeProvider(currentUrl);
  const bridgeInjectionCode = useMemo(() => buildInAppBrowserBridgeConnectorCode(), []);

  const menu = useMemo(() => {
    if (!explorers || explorers.length <= 1 || !currentUrl) {
      return undefined;
    }

    // Put current explorer first (native browser shows first item as title)
    const currentExplorer = explorers.find((e) => e.id === currentExplorerId);
    const sortedExplorers = currentExplorer
      ? [currentExplorer, ...explorers.filter((e) => e.id !== currentExplorerId)]
      : explorers;

    return sortedExplorers.map((explorer) => ({
      key: explorer.name,
      value: convertExplorerUrl(currentUrl, explorer.id) || currentUrl,
    }));
  }, [explorers, currentUrl, currentExplorerId]);

  const handleError = useLastCallback((err: any) => {
    logDebugError('inAppBrowser error', err);
  });

  const handleMenuItemSelected = useLastCallback((e: MenuItemSelectedEvent) => {
    const { key } = e.payload;
    const selectedExplorer = explorers?.find((explorer) => explorer.name === key);
    if (selectedExplorer && explorerInfo) {
      setSelectedExplorerId({
        chain: explorerInfo.chain,
        explorerId: selectedExplorer.id,
      });
    }
  });

  const handleBrowserClose = useLastCallback(() => {
    inAppBrowser.removeEventListener('loaderror', handleError);
    inAppBrowser.removeEventListener('menuitemselected', handleMenuItemSelected);
    inAppBrowser.removeEventListener('exit', handleBrowserClose);
    inAppBrowser = undefined;
    closeBrowser();

    cleanupDappBridge();
  });

  const openBrowser = useLastCallback(() => {
    try {
      const browserTitle = !title && currentUrl ? getHostnameFromUrl(currentUrl) : title;
      const browserSubtitle = subtitle === browserTitle ? undefined : subtitle;

      const ADDITIONAL_INAPP_BROWSER_OPTIONS = `,${compact([
        IS_IOS || browserTitle ? `title=${browserTitle || ''}` : undefined,
        IS_IOS || browserSubtitle ? `subtitle=${browserSubtitle || ''}` : undefined,
        currentUrl ? `shareurl=${encodeURIComponent(currentUrl)}` : undefined,
        `closebuttoncaption=${IS_IOS ? lang('Close') : 'x'}`,
        `backbuttoncaption=${lang('Back')}`,
        `reloadcaption=${lang('Reload Page')}`,
        `openinbrowsercaption=${lang(IS_IOS ? 'Open in Safari' : 'Open in Browser')}`,
        `copyurlcaption=${lang('CopyURL')}`,
        `sharecaption=${lang('Share')}`,
        `theme=${theme}`,
        `animated=${animationLevel ?? ANIMATION_LEVEL_DEFAULT > 0 ? 'yes' : 'no'}`,
      ]).join(',')}`;
      inAppBrowser = cordova.InAppBrowser.open(
        currentUrl,
        '_blank',
        INAPP_BROWSER_OPTIONS + ADDITIONAL_INAPP_BROWSER_OPTIONS,
        bridgeInjectionCode,
        menu,
      );
    } catch (err) {
      logDebugError('inAppBrowser open error', err);
      return;
    }

    const originalHide = inAppBrowser.hide;
    inAppBrowser.hide = () => {
      return new Promise<void>((resolve) => {
        originalHide?.();
        // On iOS, the animation takes some time. We have to ensure it's completed.
        if (inAppBrowser && IS_IOS_APP) {
          listenOnce(inAppBrowser, 'hidecompletion', () => resolve());
        } else {
          resolve();
        }
      });
    };

    const originalClose = inAppBrowser.close;
    inAppBrowser.close = () => {
      if (!inAppBrowser) {
        return Promise.resolve();
      }

      originalClose();

      const closedPromise = new Promise<void>((resolve) => {
        // The `waitFor` is a hack necessary to ensure the browser is fully in the closed state when the promise
        // resolves. This solves a bug: if a push notification, that opens a modal, was clicked while the in-app browser
        // was open, the browser would close, but the modal wouldn't open.
        listenOnce(inAppBrowser, 'exit', async () => {
          await waitFor(() => !inAppBrowser, 15, 20);
          resolve();
        });

        // A backup for cases when the `close()` call doesn't cause the browser to close and fire the `exit` event.
        setTimeout(resolve, CLOSE_MAX_DURATION);
      });

      // Calling `show()` while the browser is being closed causes the app to crash. So we disable the `show` method.
      inAppBrowser.show = () => undefined;
      inAppBrowser.hide = () => closedPromise;

      return closedPromise;
    };

    setupDappBridge(inAppBrowser);

    inAppBrowser.addEventListener('loaderror', handleError);
    inAppBrowser.addEventListener('menuitemselected', handleMenuItemSelected);
    inAppBrowser.addEventListener('exit', handleBrowserClose);
    inAppBrowser.show();
  });

  useEffect(() => {
    if (!currentUrl) return undefined;

    void openBrowser();

    return () => inAppBrowser?.close();
  }, [currentUrl]);

  return undefined;
}

export default memo(withGlobal((global): StateProps => {
  const { currentBrowserOptions, settings } = global;

  return {
    url: currentBrowserOptions?.url,
    title: currentBrowserOptions?.title,
    subtitle: currentBrowserOptions?.subtitle,
    theme: settings.theme,
    animationLevel: settings.animationLevel,
    selectedExplorerIds: settings.selectedExplorerIds,
    isTestnet: settings.isTestnet,
  };
})(InAppBrowser));

export function getInAppBrowser(): CustomInAppBrowserObject | undefined {
  return inAppBrowser;
}
