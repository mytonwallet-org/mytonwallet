import type { ElementRef, TeactNode } from '../../lib/teact/teact';
import React, { useRef } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from './Dropdown';

import useContextMenuHandlers from '../../hooks/useContextMenuHandlers';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownMenu from './DropdownMenu';
import MenuBackdrop from './MenuBackdrop';

interface Props<T extends string> {
  items: DropdownItem<T>[];
  rootRef?: ElementRef<HTMLDivElement>;
  onItemClick: (value: T) => void;
  withBackdrop?: boolean;
  /**
   * Fixed overrides, or ones worked out when the menu opens from where it was opened, what opened it and whether a
   * mouse or a trackpad did, as a right click does, rather than a long press
   */
  layout?: Partial<Layout> | (
    (anchor: IAnchorPosition, trigger: HTMLElement, isFromPointer: boolean) => Partial<Layout>
  );
  children: (buttonProps: {
    ref: ElementRef<HTMLDivElement | HTMLButtonElement>;
    onMouseDown: (e: React.MouseEvent) => void;
    onContextMenu: (e: React.MouseEvent) => void;
    className?: string;
  }, isMenuOpen: boolean) => TeactNode;
  menuClassName?: string;
  /** Shown over the items, as a message menu shows the message's date */
  menuHeader?: TeactNode;
  fontIconClassName?: string;
  menuPositionY?: 'top' | 'bottom';
}

export default function WithContextMenu<T extends string>({
  items,
  rootRef,
  onItemClick,
  withBackdrop,
  layout: layoutOverrides,
  children,
  menuClassName,
  menuHeader,
  fontIconClassName,
  menuPositionY = 'bottom',
}: Props<T>) {
  const buttonRef = useRef<HTMLDivElement | HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();

  const { isPortrait } = useDeviceScreen();
  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => rootRef?.current ?? document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const {
    isContextMenuOpen,
    contextMenuAnchor,
    isContextMenuFromPointer,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
  } = useContextMenuHandlers({
    elementRef: buttonRef,
    shouldDisablePropagation: true,
  });

  const getLayout = useLastCallback((): Layout => {
    const trigger = buttonRef.current;
    const overrides = typeof layoutOverrides === 'function'
      ? (contextMenuAnchor && trigger
        ? layoutOverrides(contextMenuAnchor, trigger, isContextMenuFromPointer)
        : undefined)
      : layoutOverrides;

    return {
      withPortal: true,
      doNotCoverTrigger: true,
      isCenteredHorizontally: true,
      ...overrides,
    };
  });

  const handleMenuItemSelect = useLastCallback((value: T) => {
    onItemClick(value);
  });

  return (
    <>
      {isPortrait && withBackdrop && (
        <MenuBackdrop
          isMenuOpen={isContextMenuOpen}
          contentRef={buttonRef}
          contentClassName={menuClassName}
        />
      )}
      {children(
        {
          ref: buttonRef,
          onMouseDown: handleBeforeContextMenu,
          onContextMenu: handleContextMenu,
        },
        isContextMenuOpen,
      )}
      {!!contextMenuAnchor && (
        <DropdownMenu
          ref={menuRef}
          withPortal
          shouldTranslateOptions
          isOpen={isContextMenuOpen}
          header={menuHeader}
          items={items}
          menuPositionY={menuPositionY}
          menuAnchor={contextMenuAnchor}
          bubbleClassName={menuClassName}
          fontIconClassName={fontIconClassName}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={handleMenuItemSelect}
          onClose={handleContextMenuClose}
          onCloseAnimationEnd={handleContextMenuHide}
        />
      )}
    </>
  );
}
