import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { DropdownItem } from '../../../ui/Dropdown';
import { AccountSelectorState } from '../../../../global/types';

import buildClassName from '../../../../util/buildClassName';
import { vibrate } from '../../../../util/haptics';

import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { usePrevDuringAnimationSimple } from '../../../../hooks/usePrevDuringAnimationSimple';
import { useTransitionActiveKey } from '../../../../hooks/useTransitionActiveKey';

import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';
import Transition from '../../../ui/Transition';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './AccountSelectorHeader.module.scss';

type MenuHandler = 'cards' | 'list' | 'reorder';

interface OwnProps {
  walletsCount: number;
  totalBalance?: string;
  renderingState: AccountSelectorState;
  isSensitiveDataHidden?: true;
  onViewModeChange: (state: AccountSelectorState) => void;
  onReorderClick: NoneToVoidFunction;
}

const MENU_HANDLER_TO_RENDERING_STATE: Record<MenuHandler, AccountSelectorState> = {
  cards: AccountSelectorState.Cards,
  list: AccountSelectorState.List,
  reorder: AccountSelectorState.Reorder,
};

const RENDERING_STATE_TO_MENU_HANDLER: Partial<Record<AccountSelectorState, MenuHandler>> = {
  [AccountSelectorState.Cards]: 'cards',
  [AccountSelectorState.List]: 'list',
  [AccountSelectorState.Reorder]: 'reorder',
};

const ALL_MENU_ITEMS: DropdownItem<MenuHandler>[] = [{
  value: 'cards',
  name: 'View as Cards',
  fontIcon: 'menu-cards',
}, {
  value: 'list',
  name: 'View as List',
  fontIcon: 'menu-list',
}, {
  value: 'reorder',
  name: 'Reorder',
  fontIcon: 'menu-reorder',
}];

const AccountSelectorHeader = ({
  walletsCount,
  totalBalance,
  renderingState,
  isSensitiveDataHidden,
  onViewModeChange,
  onReorderClick,
}: OwnProps) => {
  const { closeAccountSelector } = getActions();

  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag(false);
  const renderingKey = useTransitionActiveKey([walletsCount, totalBalance]);

  const menuItems = useMemo((): DropdownItem<MenuHandler>[] => {
    const currentHandler = RENDERING_STATE_TO_MENU_HANDLER[renderingState];

    return ALL_MENU_ITEMS.filter((item) => item.value !== currentHandler);
  }, [renderingState]);
  const renderingMenuItems = usePrevDuringAnimationSimple(menuItems);

  const handleMenuButtonClick = useLastCallback(() => {
    void vibrate();
    openMenu();
  });

  const handleMenuSelect = useLastCallback((handler: MenuHandler) => {
    void vibrate();
    const state = MENU_HANDLER_TO_RENDERING_STATE[handler];

    if (state === AccountSelectorState.Reorder) {
      onReorderClick();
    } else {
      onViewModeChange(state);
    }
  });

  return (
    <div className={styles.header}>
      <Button
        isRound
        className={buildClassName(styles.menuButton, styles.headerButton)}
        ariaLabel={lang('Menu')}
        onClick={handleMenuButtonClick}
      >
        <i className={buildClassName(styles.filterIcon, 'icon-filter')} aria-hidden />
      </Button>

      <Transition
        activeKey={renderingKey}
        name="fade"
        className={styles.titleWrapper}
        slideClassName={styles.title}
      >
        <div>{lang('$wallets_amount', walletsCount)}</div>
        <div className={styles.totalBalance}>
          {lang('$total_balance', { balance: isSensitiveDataHidden ? '***' : (totalBalance ?? '0') })}
        </div>
      </Transition>

      <Button
        isRound
        className={buildClassName(styles.closeButton, styles.headerButton)}
        ariaLabel={lang('Close')}
        onClick={closeAccountSelector}
      >
        <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
      </Button>

      <DropdownMenu
        isOpen={isMenuOpen}
        shouldTranslateOptions
        items={renderingMenuItems}
        className={styles.menu}
        onSelect={handleMenuSelect}
        onClose={closeMenu}
      />
    </div>
  );
};

export default memo(AccountSelectorHeader);
