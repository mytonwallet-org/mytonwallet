import type { TeactNode } from '../../../../lib/teact/teact';
import { memo, useRef, useState } from '../../../../lib/teact/teact';
import React from '../../../../lib/teact/teact';

import type { IAnchorPosition, OverviewCellSize } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { DropdownItem } from '../../../ui/Dropdown';

import buildClassName from '../../../../util/buildClassName';
import { stopEvent } from '../../../../util/domEvents';

import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLastCallback from '../../../../hooks/useLastCallback';

import ShowAllButton from '../../../common/ShowAllButton';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './OverviewCell.module.scss';

export const OVERVIEW_CELL_BODY_CLASS = 'overview-cell-body';

interface OwnProps<T, MenuValue extends string = string> {
  caption?: string;
  showAllIcon?: ShowAllIcon;
  showAllLabel?: string;
  showAllAmount?: number;
  showAllTestId?: string;
  clickArg?: T;
  menuItems?: DropdownItem<MenuValue>[];
  size?: OverviewCellSize;
  /** Fills the row when it holds the only cell */
  isStretched?: boolean;
  className?: string;
  bodyClassName?: string;
  children: TeactNode;
  onShowAllClick?: (arg: T) => void;
  onMenuItemClick?: (value: MenuValue, arg: T) => void;
}

type ShowAllIcon = 'showAll' | 'collectibles' | 'gift' | 'positions';

const SHOW_ALL_ICON_CLASS: Record<ShowAllIcon, string> = {
  showAll: 'icon-show-all',
  collectibles: 'icon-show-all-collectibles',
  gift: buildClassName('icon-gift', styles.showAllIconGift),
  positions: 'icon-show-all-positions',
};

const SIZE_CLASS: Record<OverviewCellSize, string> = {
  small: styles.sizeSmall,
  medium: styles.sizeMedium,
  big: styles.sizeBig,
};

function OverviewCell<T = undefined, MenuValue extends string = string>({
  caption,
  showAllLabel,
  showAllIcon,
  showAllAmount,
  showAllTestId,
  clickArg,
  menuItems,
  size = 'small',
  isStretched,
  className,
  bodyClassName,
  children,
  onShowAllClick,
  onMenuItemClick,
}: OwnProps<T, MenuValue>) {
  const { isPortrait } = useDeviceScreen();
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

  const titleAndBadge = (
    <span className={styles.captionTitleRow}>
      <span className={styles.captionTitle}>{caption}</span>
    </span>
  );

  const captionClassName = buildClassName(styles.caption, isPortrait && styles.captionPortrait);

  function renderCaption() {
    if (caption === undefined) return undefined;

    if (!hasRenderedMenu) return <div className={captionClassName}>{titleAndBadge}</div>;

    return (
      <span
        ref={triggerRef}
        className={buildClassName(captionClassName, styles.captionInteractive)}
        role="button"
        tabIndex={0}
        onClick={handleOpenMenu}
        onKeyDown={handleTriggerKeyDown}
      >
        {titleAndBadge}
        <i className={buildClassName('icon', 'icon-expand', styles.captionIcon)} aria-hidden />
      </span>
    );
  }

  const wrapperClassName = buildClassName(
    styles.wrapper, isPortrait && styles.portrait, isStretched && styles.stretched, SIZE_CLASS[size], className,
  );

  return (
    <div className={wrapperClassName}>
      {renderCaption()}
      <div className={styles.card}>
        <div
          className={buildClassName(
            styles.body,
            OVERVIEW_CELL_BODY_CLASS,
            isPortrait ? styles.bodyPortrait : 'custom-scroll',
            !isPortrait && onShowAllClick && styles.bodyWithShowAll,
            bodyClassName,
          )}
        >
          {children}
        </div>
        {onShowAllClick && (
          <ShowAllButton
            icon={SHOW_ALL_ICON_CLASS[showAllIcon!]}
            label={showAllLabel!}
            amount={showAllAmount}
            isFloating={!isPortrait}
            testId={showAllTestId}
            onClick={handleShowAllClick}
          />
        )}
      </div>
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
          shouldTranslateOptions
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
