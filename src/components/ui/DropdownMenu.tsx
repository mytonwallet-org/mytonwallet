import type { TeactNode } from '../../lib/teact/teact';
import React, {
  type ElementRef, memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { DropdownItem } from './Dropdown';
import type { SubMenuPosition } from './helpers/calculateSubMenuPosition';
import type { MenuPositionOptions } from './Menu';

import buildClassName from '../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import windowSize from '../../util/windowSize';
import calculateSubMenuPosition from './helpers/calculateSubMenuPosition';

import useDelayedAction from '../../hooks/useDelayedAction';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownItemContent from './DropdownItemContent';
import Menu from './Menu';

import styles from './Dropdown.module.scss';

interface OwnProps<T extends string> {
  isOpen: boolean;
  ref?: ElementRef<HTMLDivElement>;
  selectedValue?: T;
  items: DropdownItem<T>[];
  /** A line above the items, such as the date of the message the menu is for */
  header?: TeactNode;
  withPortal?: boolean;
  menuAnchor?: IAnchorPosition;
  menuPositionY?: 'top' | 'bottom';
  menuPositionX?: 'right' | 'left';
  shouldTranslateOptions?: boolean;
  className?: string;
  bubbleClassName?: string;
  /** The bubble of an item's side submenu, `bubbleClassName` by default; a menu with a header sets it apart */
  subMenuBubbleClassName?: string;
  buttonClassName?: string;
  iconClassName?: string;
  fontIconClassName?: string;
  itemDescriptionClassName?: string;
  shouldCleanup?: boolean;
  onSelect?: (value: T, e?: React.MouseEvent) => void;
  onClose: NoneToVoidFunction;
  getTriggerElement?: () => HTMLElement | undefined | null;
  getRootElement?: () => HTMLElement | undefined | null;
  getMenuElement?: () => HTMLElement | undefined | null;
  getLayout?: () => { withPortal?: boolean };
  onCloseAnimationEnd?: NoneToVoidFunction;
}

// A submenu's rows, as tall as a dropdown's, under its 0.5rem padding; its width is at most `.subMenuBubble`'s
const SUB_MENU_ROW_HEIGHT_PX = 44;
const SUB_MENU_PADDING_PX = 16;
const SUB_MENU_MAX_WIDTH_PX = 240;
// A submenu is placed by its rendered height, which `.dropdown` in `Menu.module.scss` caps at `min(60vh, 22rem)`
const SUB_MENU_MAX_HEIGHT_PX = 352;
const SUB_MENU_MAX_HEIGHT_VIEWPORT_SHARE = 0.6;
// A grace period, so the pointer's way into a submenu across the other rows keeps it open
const SUB_MENU_CLOSE_DELAY_MS = 150;

function DropdownMenu<T extends string>({
  isOpen,
  ref,
  selectedValue,
  items,
  header,
  withPortal,
  menuAnchor,
  menuPositionX,
  menuPositionY,
  shouldTranslateOptions,
  className,
  bubbleClassName,
  subMenuBubbleClassName,
  buttonClassName,
  iconClassName,
  fontIconClassName,
  itemDescriptionClassName,
  shouldCleanup,
  onSelect,
  onClose,
  getTriggerElement,
  getRootElement,
  getMenuElement,
  getLayout,
  onCloseAnimationEnd,
}: OwnProps<T>) {
  let menuRef = useRef<HTMLDivElement>();
  if (ref) {
    menuRef = ref;
  }

  const subMenuRef = useRef<HTMLDivElement>();
  const { isRtl } = useLang();
  const [subMenu, setSubMenu] = useState<{ value: T; position: SubMenuPosition }>();
  const subMenuItems = subMenu && items.find(({ value }) => value === subMenu.value)?.subItems;

  const closeSubMenu = useLastCallback(() => {
    setSubMenu(undefined);
  });
  const [scheduleSubMenuClose, cancelSubMenuClose] = useDelayedAction(closeSubMenu, SUB_MENU_CLOSE_DELAY_MS);

  const openSubMenu = useLastCallback((rowElement: HTMLElement, item: DropdownItem<T>) => {
    cancelSubMenuClose();
    const height = Math.min(
      item.subItems!.length * SUB_MENU_ROW_HEIGHT_PX + SUB_MENU_PADDING_PX,
      SUB_MENU_MAX_HEIGHT_PX,
      windowSize.get().height * SUB_MENU_MAX_HEIGHT_VIEWPORT_SHARE,
    );
    setSubMenu({
      value: item.value,
      position: calculateSubMenuPosition(rowElement, SUB_MENU_MAX_WIDTH_PX, height, isRtl),
    });
  });

  useEffect(() => {
    if (!isOpen) setSubMenu(undefined);
  }, [isOpen]);

  // With a submenu open, a press outside both menus closes the menu, and one in either keeps it. The menu's backdrop
  // stays, so the press's `click` does not reach the element beneath.
  useEffect(() => {
    if (!subMenu) return undefined;

    const handleMouseDown = (e: MouseEvent) => {
      const target = e.target as Node;
      if (menuRef.current?.contains(target) || subMenuRef.current?.contains(target)) return;

      e.preventDefault();
      e.stopPropagation();
      onClose();
    };

    document.addEventListener('mousedown', handleMouseDown);
    return () => document.removeEventListener('mousedown', handleMouseDown);
  }, [menuRef, onClose, subMenu]);

  // Dynamic (anchor) placement below is computed from geometry and is already direction-correct.
  // The static branch places the menu by a physical CSS edge (`.left`/`.right`), so mirror the side
  // for RTL - otherwise it stays pinned to the physical right edge and opens off-screen / clipped
  const staticPositionX = isRtl ? (menuPositionX === 'right' ? 'left' : 'right') : menuPositionX;

  // Create position options
  const menuPositionOptions: MenuPositionOptions = menuAnchor && getTriggerElement && getRootElement && getMenuElement
    ? {
      anchor: menuAnchor,
      getTriggerElement,
      getRootElement,
      getMenuElement,
      getLayout,
    }
    : menuAnchor && getRootElement && getMenuElement
      ? {
        anchor: menuAnchor,
        getRootElement,
        getMenuElement,
        getLayout,
        positionX: menuPositionX,
        positionY: menuPositionY,
      }
      : {
        anchor: menuAnchor,
        positionX: staticPositionX,
        positionY: menuPositionY,
      };

  const handleItemClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>, value: T) => {
    e.stopPropagation();
    const item = items.find((option) => option.value === value);
    // A click keeps the submenu that hovering the item has already opened
    if (item?.subItems && !IS_TOUCH_ENV) {
      openSubMenu(e.currentTarget, item);
      return;
    }

    onSelect?.(value, e);
    if (!item?.shouldKeepOpen) onClose();
  });

  const handleItemMouseEnter = useLastCallback((e: React.MouseEvent<HTMLButtonElement>, value: T) => {
    const item = items.find((option) => option.value === value);
    if (item?.subItems) {
      openSubMenu(e.currentTarget, item);
    } else if (subMenu) {
      scheduleSubMenuClose();
    }
  });

  const handleSubItemClick = useLastCallback((e: React.MouseEvent, value: T) => {
    e.stopPropagation();
    onSelect?.(value, e);
    onClose();
  });

  function renderSubMenuChevron() {
    return <i className={buildClassName('icon-chevron-right', styles.subMenuChevron)} aria-hidden />;
  }

  function renderItem(item: DropdownItem<T>, index: number, onClick: typeof handleItemClick) {
    const hasSubMenu = Boolean(item.subItems) && !IS_TOUCH_ENV;
    const fullButtonClassName = buildClassName(
      styles.item,
      (item.icon || item.fontIcon) && styles.item_with_icon,
      item.withDelimiter && index > 0 && styles.delimiter,
      item.withDelimiterAfter && styles.delimiterAfter,
      selectedValue === item.value && styles.item_selected,
      hasSubMenu && subMenu?.value === item.value && styles.item_expanded,
      buttonClassName,
      'capture-scroll',
    );
    return (
      <DropdownItemContent
        key={item.value}
        item={item}
        shouldTranslate={shouldTranslateOptions}
        className={fullButtonClassName}
        iconClassName={iconClassName}
        fontIconClassName={fontIconClassName}
        itemClassName="menuItemName"
        itemDescriptionClassName={itemDescriptionClassName}
        suffix={hasSubMenu ? renderSubMenuChevron() : undefined}
        isExpanded={hasSubMenu ? subMenu?.value === item.value : undefined}
        onClick={onClick}
        onMouseEnter={IS_TOUCH_ENV || onClick !== handleItemClick ? undefined : handleItemMouseEnter}
      />
    );
  }

  return (
    <>
      <Menu
        menuRef={menuRef}
        isOpen={isOpen}
        type="dropdown"
        withPortal={withPortal}
        className={className}
        bubbleClassName={bubbleClassName}
        shouldCleanup={shouldCleanup}
        noCloseOnBackdrop={Boolean(subMenu)}
        positionKey={items.length}
        onClose={onClose}
        onCloseAnimationEnd={onCloseAnimationEnd}
        {...menuPositionOptions}
      >
        {header !== undefined && <div className={styles.header}>{header}</div>}
        {items.map((item, index) => renderItem(item, index, handleItemClick))}
      </Menu>
      {Boolean(subMenuItems?.length) && (
        <Menu
          menuRef={subMenuRef}
          isOpen={isOpen && Boolean(subMenu)}
          type="dropdown"
          withPortal
          className={className}
          anchor={subMenu!.position}
          positionX={subMenu!.position.positionX}
          transformOriginY={subMenu!.position.originY}
          bubbleClassName={buildClassName(subMenuBubbleClassName ?? bubbleClassName, styles.subMenuBubble)}
          noBackdrop
          noHistoryBack
          onMouseEnter={cancelSubMenuClose}
          onMouseLeave={scheduleSubMenuClose}
          onClose={closeSubMenu}
        >
          {subMenuItems.map((item, index) => renderItem(item, index, handleSubItemClick))}
        </Menu>
      )}
    </>
  );
}

export default memo(DropdownMenu);
