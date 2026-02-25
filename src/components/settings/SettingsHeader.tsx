import React, { type ElementRef, memo, useLayoutEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import { IS_CAPACITOR } from '../../config';
import { selectCurrentAccount, selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useElementVisibility from '../../hooks/useElementVisibility';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useWindowSize from '../../hooks/useWindowSize';

import AccountRenameModal from '../main/modals/accountSelector/AccountRenameModal';
import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';

import styles from './Settings.module.scss';

type StateProps = {
  currentAccountId?: string;
  currentAccountTitle?: string;
};

type OwnProps = {
  isInsideModal?: boolean;
  isViewMode: boolean;
  isActive: boolean;
  isScrolled: boolean;
  currentWalletRef?: ElementRef<HTMLDivElement>;
  onCloseSettings: NoneToVoidFunction;
  onRemoveClick: NoneToVoidFunction;
};

function SettingsHeader({
  currentAccountId,
  currentAccountTitle,
  isInsideModal,
  isViewMode,
  isActive,
  isScrolled,
  currentWalletRef,
  onCloseSettings,
  onRemoveClick,
}: OwnProps & StateProps) {
  const { openReceiveModal } = getActions();
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const { height: windowHeight, width: windowWidth } = useWindowSize();

  const menuButtonRef = useRef<HTMLButtonElement>();
  const headerRef = useRef<HTMLDivElement>();
  const dropdownMenuRef = useRef<HTMLDivElement>();

  const [settingsHeaderHeight, setSettingsHeaderHeight] = useState(0);
  const [isRenameModalOpen, openRenameModal, closeRenameModal] = useFlag();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();

  const getTriggerElement = useLastCallback(() => menuButtonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => dropdownMenuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    preferredPositionX: 'right',
  }));

  type MenuHandler = 'rename' | 'remove';

  const menuItems = useMemo<DropdownItem<MenuHandler>[]>(() => [
    {
      value: 'rename',
      name: 'Rename',
      fontIcon: 'menu-rename',
    },
    {
      value: 'remove',
      name: 'Remove',
      fontIcon: 'menu-trash',
      isDangerous: true,
    },
  ], []);

  const handleRenameClick = useLastCallback(() => {
    void vibrate();
    openRenameModal();
  });

  const handleRemoveClick = useLastCallback(() => {
    void vibrate();
    onRemoveClick();
  });

  const handleMenuButtonClick = useLastCallback(() => {
    if (!menuButtonRef.current) return;

    const rect = menuButtonRef.current.getBoundingClientRect();
    setMenuAnchor({
      x: rect.right,
      y: rect.bottom,
    });
    openMenu();
    void vibrate();
  });

  const handleMenuItemSelect = useLastCallback((value: MenuHandler) => {
    if (value === 'rename') {
      handleRenameClick();
    } else if (value === 'remove') {
      handleRemoveClick();
    }
  });

  const handleMenuClose = useLastCallback(() => {
    closeMenu();
  });

  const handleMenuCloseAnimationEnd = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  useLayoutEffect(() => {
    if (isInsideModal) {
      setSettingsHeaderHeight(0);
      return;
    }

    const element = headerRef.current;
    if (!element) return;

    setSettingsHeaderHeight(element.getBoundingClientRect().height);
  }, [isInsideModal, isPortrait, windowHeight, windowWidth]);

  const { isVisible } = useElementVisibility({
    isDisabled: !isPortrait || !isActive,
    targetRef: currentWalletRef,
    rootMargin: `-${settingsHeaderHeight}px 0px 0px 0px`,
  });

  if (isInsideModal) {
    return (
      <ModalHeader
        title={lang('Settings')}
        onClose={!isPortrait ? onCloseSettings : undefined}
        className={styles.modalHeader}
      />
    );
  }

  if (!IS_CAPACITOR) {
    return (
      <div
        ref={headerRef}
        className={buildClassName(
          styles.header,
          styles.mobileHeader,
          'with-notch-on-scroll',
          isScrolled && 'is-scrolled',
        )}
      >
        <span className={styles.headerWalletName}>
          {lang('Settings')}
        </span>
      </div>
    );
  }

  return (
    <>
      <div
        ref={headerRef}
        className={buildClassName(
          styles.header,
          styles.headerWithWalletName,
          'with-notch-on-scroll',
          !isVisible && 'is-scrolled',
        )}
      >
        <Button
          isSimple
          className={buildClassName(styles.headerButton, isViewMode && styles.hidden)}
          onClick={!isViewMode ? openReceiveModal : undefined}
        >
          <i className="icon-qr-code" aria-hidden />
        </Button>

        <Transition
          name="fade"
          activeKey={!isVisible ? 1 : 0}
          className={styles.headerWalletNameTransition}
          slideClassName={styles.headerWalletNameSlide}
        >
          {!isVisible && (
            <span className={styles.headerWalletName}>
              {currentAccountTitle || lang('Settings')}
            </span>
          )}
        </Transition>

        <Button
          ref={menuButtonRef}
          isSimple
          className={styles.headerButton}
          onClick={handleMenuButtonClick}
        >
          <i className={buildClassName('icon-menu-dots', styles.headerButton_small)} aria-hidden />
        </Button>
      </div>

      {menuAnchor && (
        <DropdownMenu
          ref={dropdownMenuRef}
          isOpen={isMenuOpen}
          withPortal
          menuAnchor={menuAnchor}
          menuPositionX="right"
          items={menuItems}
          shouldTranslateOptions
          bubbleClassName={styles.dropdownMenu}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={handleMenuItemSelect}
          onClose={handleMenuClose}
          onCloseAnimationEnd={handleMenuCloseAnimationEnd}
        />
      )}

      {currentAccountId && (
        <AccountRenameModal
          isOpen={isRenameModalOpen}
          accountId={currentAccountId}
          onClose={closeRenameModal}
        />
      )}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const currentAccountTitle = selectCurrentAccount(global)?.title;
  return {
    currentAccountId,
    currentAccountTitle,
  };
})(SettingsHeader));
