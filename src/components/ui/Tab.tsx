import React, { useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from './Dropdown';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from './DropdownMenu';

import styles from './Tab.module.scss';

type OwnProps = {
  isActive?: boolean;
  icon?: string;
  title: string;
  menuItems?: DropdownItem[];
  menuClassName?: string;
  menuPositionX?: 'left' | 'right';
  className?: string;
  onClick: (arg: number) => void;
  clickArg: number;
  onMenuItemClick?: (value: string) => void;
  onActiveClick?: NoneToVoidFunction;
};

function Tab({
  isActive,
  icon,
  title,
  menuItems,
  menuClassName,
  menuPositionX,
  className,
  onClick,
  clickArg,
  onMenuItemClick,
  onActiveClick,
}: OwnProps) {
  const menuRef = useRef<HTMLDivElement>();
  const contentRef = useRef<HTMLDivElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();
  const hasMenu = Boolean(menuItems?.length);
  const isMenuOpen = Boolean(menuAnchor);

  const getTriggerElement = useLastCallback(() => contentRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    preferredPositionX: menuPositionX,
  }));
  const closeMenu = useLastCallback(() => setMenuAnchor(undefined));

  const handleClick = useLastCallback(() => {
    if (isActive && !hasMenu) {
      onActiveClick?.();
      return;
    }

    if (!isActive) {
      onClick(clickArg);
      return;
    }

    if (isMenuOpen) {
      closeMenu();
    } else {
      const { right: x, y, height } = contentRef.current!.getBoundingClientRect();
      setMenuAnchor({ x, y: y + height });
    }
  });

  return (
    <div
      className={buildClassName(styles.Tab, isActive && styles.Tab_active, className, hasMenu && styles.interactive)}
      onClick={handleClick}
    >
      <span className={styles.content} ref={contentRef}>
        {icon && <i className={buildClassName(icon, styles.icon)} aria-hidden />}
        {title}
        {hasMenu && (
          <i className={buildClassName('icon-caret-down', styles.caretIcon)} aria-hidden />
        )}
      </span>
      {hasMenu && (
        <DropdownMenu
          isOpen={isMenuOpen}
          ref={menuRef}
          items={menuItems}
          withPortal
          className={menuClassName}
          buttonClassName={styles.menuItem}
          menuPositionX={menuPositionX || 'right'}
          menuAnchor={menuAnchor}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={onMenuItemClick}
          onClose={closeMenu}
        />
      )}
    </div>
  );
}

export default Tab;
