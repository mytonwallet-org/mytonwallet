import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { DropdownItem } from './Dropdown';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from './Button';
import Dropdown from './Dropdown';
import DropdownMenu from './DropdownMenu';

import styles from './IFrameBrowser.module.scss';
import modalStyles from './Modal.module.scss';

type MenuHandler = 'reload' | 'openInBrowser' | 'copyUrl' | 'close';

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

interface OwnProps {
  title?: string;
  dropdownItems: DropdownItem[];
  currentExplorerId?: string;
  shouldShowDropdown: boolean;
  onExplorerChange: (explorerId: string) => void;
  onMenuItemClick: (value: MenuHandler) => void;
}

function IFrameBrowserHeader({
  title,
  dropdownItems,
  currentExplorerId,
  shouldShowDropdown,
  onExplorerChange,
  onMenuItemClick,
}: OwnProps) {
  const lang = useLang();

  const menuRef = useRef<HTMLDivElement>();
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<{ x: number; y: number } | undefined>();

  const isMenuOpen = Boolean(menuAnchor);

  const getTriggerElement = useLastCallback(() => menuButtonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));
  const closeMenu = useLastCallback(() => setMenuAnchor(undefined));

  const handleMenuButtonClick = useLastCallback(() => {
    if (isMenuOpen) {
      closeMenu();
      return;
    }

    const button = menuButtonRef.current;
    if (!button) return;

    const { right: x, y, height } = button.getBoundingClientRect();
    setMenuAnchor({ x, y: y + height });
  });

  const handleMenuItemSelect = useLastCallback((value: MenuHandler) => {
    closeMenu();
    onMenuItemClick(value);
  });

  return (
    <div
      className={buildClassName(
        modalStyles.header,
        modalStyles.header_wideContent,
        styles.modalHeader,
        isMenuOpen && 'is-menu-open',
      )}
    >
      <div className={buildClassName(modalStyles.title, styles.title)}>
        {shouldShowDropdown ? (
          <Dropdown<string>
            items={dropdownItems}
            selectedValue={currentExplorerId}
            theme="light"
            menuPositionX="left"
            shouldTranslateOptions
            itemClassName={styles.dropdownValue}
            onChange={onExplorerChange}
          />
        ) : title}
      </div>

      <DropdownMenu
        isOpen={isMenuOpen}
        ref={menuRef}
        items={MENU_ITEMS}
        withPortal
        shouldTranslateOptions
        menuPositionX="right"
        menuAnchor={menuAnchor}
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onSelect={handleMenuItemSelect}
        onClose={closeMenu}
      />

      <Button
        ref={menuButtonRef}
        isSimple
        className={modalStyles.menuButton}
        ariaLabel={lang('Menu')}
        onClick={handleMenuButtonClick}
      >
        <i className={buildClassName(modalStyles.menuIcon, 'icon-menu-dots')} aria-hidden />
      </Button>
    </div>
  );
}

export default memo(IFrameBrowserHeader);
