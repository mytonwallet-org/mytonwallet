import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { DropdownItem } from '../ui/Dropdown';
import type { TabWithProperties } from '../ui/TabList';

import { selectIsOffRampAllowed } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { compact } from '../../util/iteratees';
import { openMultisend } from '../../util/openMultisend';
import { getChainBySlug } from '../../util/tokens';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TabList from '../ui/TabList';

import styles from './SentTabs.module.scss';

interface OwnProps {
  className?: string;
}

interface StateProps {
  isOffRampAllowed?: boolean;
}

const enum TabContent {
  Send,
  Sell,
}

function SentTabs({ className, isOffRampAllowed }: OwnProps & StateProps) {
  const { openOffRampWidgetModal, cancelTransfer } = getActions();
  const lang = useLang();

  const handleMultisendOpen = useLastCallback(() => {
    vibrate();
    void openMultisend();
  });

  const handleSwitchTab = useLastCallback((index: TabContent) => {
    if (index === TabContent.Sell) {
      vibrate();
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

  return (
    <div className={buildClassName(styles.root, className)}>
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

export default memo(withGlobal((global): StateProps => {
  const chain = getChainBySlug(global.currentTransfer.tokenSlug);

  return {
    isOffRampAllowed: selectIsOffRampAllowed(global, chain),
  };
})(SentTabs));
