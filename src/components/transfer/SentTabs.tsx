import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { LangFn } from '../../hooks/useLang';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';
import type { TabWithProperties } from '../ui/TabList';

import { MYTONWALLET_MULTISEND_DAPP_URL } from '../../config';
import { selectIsOffRampAllowed } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { compact } from '../../util/iteratees';
import { getTranslation } from '../../util/langProvider';
import { openUrl } from '../../util/openUrl';
import { getHostnameFromUrl } from '../../util/url';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';
import TabList from '../ui/TabList';

import styles from './SentTabs.module.scss';

interface OwnProps {
  isInsideModal?: boolean;
}

interface StateProps {
  isOffRampAllowed?: boolean;
}

const enum TabContent {
  Send,
  Sell,
}

function SentTabs({ isInsideModal, isOffRampAllowed }: OwnProps & StateProps) {
  const { openOffRampWidgetModal, cancelTransfer } = getActions();
  const lang = useLang();

  const handleMultisendOpen = useLastCallback(() => {
    void vibrate();
    void openUrl(MYTONWALLET_MULTISEND_DAPP_URL, {
      title: getTranslation('Multisend'),
      subtitle: getHostnameFromUrl(MYTONWALLET_MULTISEND_DAPP_URL),
    });
  });

  const handleSwitchTab = useLastCallback((index: TabContent) => {
    if (index === TabContent.Sell) {
      void vibrate();
      cancelTransfer();
      openOffRampWidgetModal();
    }
  });

  const multisendMenuItem: DropdownItem = useMemo(() => ({
    name: lang('Multisend'),
    value: 'multisend',
    fontIcon: 'menu-multisend',
  }), [lang]);

  const tabs: TabWithProperties<TabContent>[] = useMemo(() => {
    return compact<TabWithProperties<TabContent> | undefined>([
      {
        id: TabContent.Send,
        title: lang('Send'),
        className: styles.tab,
        menuClassName: styles.menuWrapper,
        menuPositionX: 'left',
        menuItems: [multisendMenuItem],
        onMenuItemClick: handleMultisendOpen,
      },
      isOffRampAllowed ? {
        id: TabContent.Sell,
        title: lang('Sell'),
        className: styles.tab,
      } : undefined,
    ]);
  }, [isOffRampAllowed, lang, multisendMenuItem, handleMultisendOpen]);

  if (!isOffRampAllowed && !isInsideModal) {
    return undefined;
  }

  if (!isOffRampAllowed) {
    return <DropdownButton lang={lang} onMultisendClick={handleMultisendOpen} />;
  }

  return (
    <div className={buildClassName(styles.root, isInsideModal && styles.rootInsideModal)}>
      <TabList
        tabs={tabs}
        activeTab={TabContent.Send}
        onSwitchTab={handleSwitchTab}
        className={buildClassName(styles.tabs, 'content-tabslist')}
        overlayClassName={styles.tabsOverlay}
      />
    </div>
  );
}

function DropdownButton({ lang, onMultisendClick }: { lang: LangFn; onMultisendClick: NoneToVoidFunction }) {
  const [isMenuOpen, openMenu, closeMenu] = useFlag(false);
  const contentRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();

  const menuItems: DropdownItem[] = useMemo(() => [{
    name: lang('Multisend'),
    value: 'multisend',
    fontIcon: 'menu-multisend',
  }], [lang]);

  const getTriggerElement = useLastCallback(() => contentRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    doNotCoverTrigger: true,
    topShiftY: 5,
    preferredPositionX: 'right',
    isCenteredHorizontally: true,
  }));

  return (
    <div className={styles.headerWrapper}>
      <Button ref={contentRef} isText className={styles.headerButton} onClick={openMenu}>
        {lang('Send')}
        <i className="icon-caret-down" aria-hidden />
      </Button>
      <DropdownMenu
        isOpen={isMenuOpen}
        ref={menuRef}
        menuPositionX="left"
        items={menuItems}
        shouldTranslateOptions
        bubbleClassName={styles.menu}
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onClose={closeMenu}
        onSelect={onMultisendClick}
      />
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isOffRampAllowed: selectIsOffRampAllowed(global),
  };
})(SentTabs));
