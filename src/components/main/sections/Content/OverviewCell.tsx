import type { TeactNode } from '../../../../lib/teact/teact';
import { memo, useRef, useState } from '../../../../lib/teact/teact';
import React from '../../../../lib/teact/teact';

import type { IAnchorPosition } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { DropdownItem } from '../../../ui/Dropdown';

import buildClassName from '../../../../util/buildClassName';
import { stopEvent } from '../../../../util/domEvents';
import { formatNumber } from '../../../../util/formatNumber';

import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './OverviewCell.module.scss';

interface OwnProps<T, MenuValue extends string = string> {
  caption: string;
  showAllIcon: string;
  showAllLabel: string;
  showAllAmount?: number;
  clickArg?: T;
  menuItems?: DropdownItem<MenuValue>[];
  selectedMenuValue?: MenuValue;
  className?: string;
  children: TeactNode;
  onShowAllClick?: (arg: T) => void;
  onMenuItemClick?: (value: MenuValue, arg: T) => void;
}

function OverviewCell<T = undefined, MenuValue extends string = string>({
  caption,
  showAllLabel,
  showAllIcon,
  showAllAmount,
  clickArg,
  menuItems,
  selectedMenuValue,
  className,
  children,
  onShowAllClick,
  onMenuItemClick,
}: OwnProps<T, MenuValue>) {
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>(undefined);
  const triggerRef = useRef<HTMLSpanElement>();
  const menuRef = useRef<HTMLDivElement>();
  const isMenuOpen = Boolean(menuAnchor);
  const renderedMenuItems = useCurrentOrPrev(isMenuOpen ? menuItems : undefined, true) ?? menuItems;
  const hasRenderedMenu = Boolean(renderedMenuItems?.length);

  const handleShowAllClick = useLastCallback(() => {
    onShowAllClick?.(clickArg as T);
  });

  const handleMenuSelect = useLastCallback((value: MenuValue) => {
    onMenuItemClick?.(value, clickArg as T);
  });

  const handleOpenMenu = useLastCallback((e: React.MouseEvent<HTMLSpanElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    setMenuAnchor({ x: rect.left + rect.width / 2, y: rect.top });
  });

  const handleTriggerKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLSpanElement>) => {
    if (e.code !== 'Enter' && e.code !== 'Space') return;

    stopEvent(e);

    const rect = e.currentTarget.getBoundingClientRect();
    setMenuAnchor({
      x: rect.left + rect.width / 2,
      y: rect.top,
    });
  });

  const handleCloseMenu = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  const getTriggerElement = useLastCallback(() => triggerRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    isCenteredHorizontally: true,
    preferredPositionX: 'left',
    preferredPositionY: 'top',
    doNotCoverTrigger: true,
  }));

  return (
    <div className={buildClassName(styles.wrapper, className)}>
      <div className={styles.card}>
        <div className={styles.body}>
          {children}
        </div>
        {onShowAllClick && (
          <Button isSimple className={styles.showAll} onClick={handleShowAllClick}>
            <i className={buildClassName(styles.showAllIcon, showAllIcon)} aria-hidden />
            <span className={styles.showAllLabel}>{showAllLabel}</span>
            {Boolean(showAllAmount) && (
              <strong className={styles.showAllAmount}>
                {formatNumber(showAllAmount)}
              </strong>
            )}
          </Button>
        )}
      </div>
      {hasRenderedMenu ? (
        <span
          ref={triggerRef}
          className={buildClassName(styles.caption, styles.captionInteractive)}
          role="button"
          tabIndex={0}
          onClick={handleOpenMenu}
          onKeyDown={handleTriggerKeyDown}
        >
          {caption}
          <i className={buildClassName('icon', 'icon-expand', styles.captionIcon)} aria-hidden />
        </span>
      ) : (
        <div className={styles.caption}>{caption}</div>
      )}
      {hasRenderedMenu && (
        <DropdownMenu
          isOpen={isMenuOpen}
          ref={menuRef}
          withPortal
          menuAnchor={menuAnchor}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          items={renderedMenuItems}
          selectedValue={selectedMenuValue}
          bubbleClassName={styles.menu}
          shouldCleanup
          onSelect={handleMenuSelect}
          onClose={handleCloseMenu}
        />
      )}
    </div>
  );
}

export default memo(OverviewCell);
