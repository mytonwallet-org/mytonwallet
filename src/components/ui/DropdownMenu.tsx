import React, { type ElementRef, memo, useRef } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { DropdownItem } from './Dropdown';
import type { MenuPositionOptions } from './Menu';

import buildClassName from '../../util/buildClassName';

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
  withPortal?: boolean;
  menuAnchor?: IAnchorPosition;
  menuPositionY?: 'top' | 'bottom';
  menuPositionX?: 'right' | 'left';
  shouldTranslateOptions?: boolean;
  className?: string;
  bubbleClassName?: string;
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

function DropdownMenu<T extends string>({
  isOpen,
  ref,
  selectedValue,
  items,
  withPortal,
  menuAnchor,
  menuPositionX,
  menuPositionY,
  shouldTranslateOptions,
  className,
  bubbleClassName,
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

  const { isRtl } = useLang();

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

  const handleItemClick = useLastCallback((e: React.MouseEvent, value: T) => {
    e.stopPropagation();
    onSelect?.(value, e);
    onClose();
  });

  return (
    <Menu
      menuRef={menuRef}
      isOpen={isOpen}
      type="dropdown"
      withPortal={withPortal}
      className={className}
      bubbleClassName={bubbleClassName}
      shouldCleanup={shouldCleanup}
      onClose={onClose}
      onCloseAnimationEnd={onCloseAnimationEnd}
      {...menuPositionOptions}
    >
      {items.map((item, index) => {
        const fullButtonClassName = buildClassName(
          styles.item,
          (item.icon || item.fontIcon) && styles.item_with_icon,
          item.withDelimiter && index > 0 && styles.delimiter,
          item.withDelimiterAfter && styles.delimiterAfter,
          selectedValue === item.value && styles.item_selected,
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
            onClick={handleItemClick}
          />
        );
      })}
    </Menu>
  );
}

export default memo(DropdownMenu);
