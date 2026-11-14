import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { DropdownItem } from '../../../ui/Dropdown';
import { AccountSelectorState } from '../../../../global/types';

import { SENSITIVE_DATA_MASK } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import getTestId from '../../../../util/getTestId';
import { vibrate } from '../../../../util/haptics';
import { toNativeDigits } from '../../../../util/nativeDigits';

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
  isActive?: boolean;
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
  isActive,
  onViewModeChange,
  onReorderClick,
}: OwnProps) => {
  const { closeAccountSelector } = getActions();

  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag(false);
  const renderingKey = useTransitionActiveKey([walletsCount, totalBalance]);

  // The menu stays mounted while closed, so only the active slide's copy carries the id
  const listTestId = isActive ? getTestId('wallets_view_list') : undefined;

  const menuItems = useMemo((): DropdownItem<MenuHandler>[] => {
    const currentHandler = RENDERING_STATE_TO_MENU_HANDLER[renderingState];
    const items = ALL_MENU_ITEMS.filter((item) => item.value !== currentHandler);

    return listTestId ? items.map((item) => (item.value === 'list' ? { ...item, testId: listTestId } : item)) : items;
  }, [renderingState, listTestId]);
  const renderingMenuItems = usePrevDuringAnimationSimple(menuItems);

  const handleMenuButtonClick = useLastCallback(() => {
    vibrate();
    openMenu();
  });

  const handleMenuSelect = useLastCallback((handler: MenuHandler) => {
    vibrate();
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
        testId={isActive ? getTestId('wallets_menu_button') : undefined}
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
        <div>{toNativeDigits(lang('$wallets_amount', walletsCount) as string)}</div>
        <div className={styles.totalBalance}>
          {lang('$total_balance', { balance: isSensitiveDataHidden ? SENSITIVE_DATA_MASK : (totalBalance ?? '0') })}
        </div>
      </Transition>

      <Button
        isRound
        className={buildClassName(styles.closeButton, styles.headerButton)}
        ariaLabel={lang('Close')}
        testId={isActive ? getTestId('nav_close') : undefined}
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
