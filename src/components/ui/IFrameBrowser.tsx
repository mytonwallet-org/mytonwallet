import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { DropdownItem } from './Dropdown';

import { copyTextToClipboard } from '../../util/clipboard';
import { useIFrameBridgeProvider } from '../../util/embeddedDappBridge/provider/useIFrameBridgeProvider';
import { openUrl } from '../../util/openUrl';
import { shareUrl } from '../../util/share';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Modal from './Modal';
import ModalHeader from './ModalHeader';

import styles from './IFrameBrowser.module.scss';

interface StateProps {
  url?: string;
  title?: string;
}

type MenuHandler = 'reload' | 'openInBrowser' | 'copyUrl' | 'share' | 'close';

const TITLES = {
  'tonscan.org': 'TON Explorer',
  'multisend.mytonwallet.io': 'Multi-Send',
  'localhost:4323': 'Multi-Send',
};

const MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  value: 'reload',
  name: 'Reload',
  fontIcon: 'menu-reload',
}, {
  value: 'openInBrowser',
  name: 'Open in Browser',
  fontIcon: 'menu-globe',
}, {
  value: 'copyUrl',
  name: 'Copy Link',
  fontIcon: 'menu-copy',
}, {
  value: 'close',
  name: 'Close',
  fontIcon: 'menu-close',
  withDelimiter: true,
}];

function IFrameBrowser({
  url, title,
}: StateProps) {
  const { closeBrowser, showToast } = getActions();
  const lang = useLang();

  const iframeRef = useRef<HTMLIFrameElement>();

  const { setupDappBridge } = useIFrameBridgeProvider(url);

  const host = useMemo(() => url && (new URL(url)).host, [url]);
  const renderingTitle = useCurrentOrPrev(title || (host && (TITLES[host as keyof typeof TITLES] || host)));

  const handleMenuItemClick = useLastCallback((value: MenuHandler) => {
    if (!url) return;

    const frame = iframeRef.current!;

    switch (value) {
      case 'reload':
        frame.src = 'about:blank';
        frame.addEventListener('load', () => {
          frame.src = url;
        }, { once: true });

        break;

      case 'openInBrowser':
        void openUrl(url, { isExternal: true });
        break;

      case 'copyUrl':
        void copyTextToClipboard(url);
        showToast({ message: lang('URL was copied!'), icon: 'icon-copy' });
        break;

      case 'share':
        void shareUrl(url, renderingTitle);
        break;

      case 'close':
        closeBrowser();
        break;
    }
  });

  return (
    <Modal isOpen={Boolean(url)} dialogClassName={styles.dialog} onClose={closeBrowser}>
      <ModalHeader
        title={renderingTitle}
        menuItems={MENU_ITEMS}
        onMenuItemClick={handleMenuItemClick}
        className={styles.modalHeader}
      />
      <iframe
        ref={iframeRef}
        title={renderingTitle}
        src={url}
        className={styles.iframe}
        allow="web-share; clipboard-write"
        onLoad={setupDappBridge}
      />
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { currentBrowserOptions } = global;

  return {
    url: currentBrowserOptions?.url,
    title: currentBrowserOptions?.title,
  };
})(IFrameBrowser));
