import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';

import { copyTextToClipboard } from '../../util/clipboard';
import { useIFrameBridgeProvider } from '../../util/embeddedDappBridge/provider/useIFrameBridgeProvider';
import { logDebugError } from '../../util/logs';
import { openUrl } from '../../util/openUrl';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useExplorerUrl from '../../hooks/useExplorerUrl';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import IFrameBrowserHeader from './IFrameBrowserHeader';
import Modal from './Modal';

import styles from './IFrameBrowser.module.scss';

interface StateProps {
  url?: string;
  title?: string;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
  isTestnet?: boolean;
}

type MenuHandler = 'reload' | 'openInBrowser' | 'copyUrl' | 'close';

const TITLES: Record<string, string> = {
  'tonscan.org': 'TON Explorer',
  'multisend.mytonwallet.io': 'Multi-Send',
  'localhost:4323': 'Multi-Send',
};

function IFrameBrowser({
  url, title, selectedExplorerIds, isTestnet,
}: StateProps) {
  const { closeBrowser, showToast, setSelectedExplorerId } = getActions();
  const lang = useLang();

  const iframeRef = useRef<HTMLIFrameElement>();
  // `reloadKey` forces iframe remount for reload functionality without direct DOM mutation
  const [reloadKey, setReloadKey] = useState(0);

  const {
    currentUrl,
    currentExplorerId,
    dropdownItems,
    handleExplorerChange,
  } = useExplorerUrl({
    url,
    selectedExplorerIds,
    isTestnet,
    onExplorerChange: (chain, explorerId) => {
      setSelectedExplorerId({ chain, explorerId });
      // Force iframe remount to reload with new URL
      setReloadKey((prev) => prev + 1);
    },
  });

  // The bridge needs to know the current page URL to validate the iframe origin correctly
  const { setupDappBridge } = useIFrameBridgeProvider(currentUrl);
  const renderingTitle = useCurrentOrPrev(title || getTitleFromUrl(currentUrl));
  const shouldShowDropdown = dropdownItems.length > 1 && Boolean(currentExplorerId);

  const handleMenuItemClick = useLastCallback((value: MenuHandler) => {
    switch (value) {
      case 'reload': {
        if (currentUrl) {
          // Force iframe remount to reload
          setReloadKey((prev) => prev + 1);
        }
        break;
      }

      case 'openInBrowser':
        if (currentUrl) {
          void openUrl(currentUrl, { isExternal: true });
        }
        break;

      case 'copyUrl':
        if (currentUrl) {
          void copyTextToClipboard(currentUrl);
          showToast({ message: lang('URL Copied'), icon: 'icon-copy' });
        }
        break;

      case 'close':
        closeBrowser();
        break;
    }
  });

  return (
    <Modal
      isOpen={Boolean(url)}
      dialogClassName={styles.dialog}
      onClose={closeBrowser}
    >
      <IFrameBrowserHeader
        title={renderingTitle}
        dropdownItems={dropdownItems}
        currentExplorerId={currentExplorerId}
        shouldShowDropdown={shouldShowDropdown}
        onExplorerChange={handleExplorerChange}
        onMenuItemClick={handleMenuItemClick}
      />
      <iframe
        key={reloadKey}
        ref={iframeRef}
        title={renderingTitle}
        src={currentUrl}
        className={styles.iframe}
        allow="web-share; clipboard-write"
        onLoad={setupDappBridge}
      />
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { currentBrowserOptions, settings } = global;

  return {
    url: currentBrowserOptions?.url,
    title: currentBrowserOptions?.title,
    selectedExplorerIds: settings.selectedExplorerIds,
    isTestnet: settings.isTestnet,
  };
})(IFrameBrowser));

function getTitleFromUrl(url: string | undefined): string | undefined {
  if (!url) return undefined;

  try {
    const host = new URL(url).host;

    return TITLES[host] || host;
  } catch (err: any) {
    logDebugError('[IFrameBrowser][getTitleFromUrl]', err);
    return undefined;
  }
}
