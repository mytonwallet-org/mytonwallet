import React, { memo, useMemo, useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { DropdownItem } from '../ui/Dropdown';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';
import AgentReportIcon from './AgentReportIcon';

interface OwnProps {
  className?: string;
  menuClassName?: string;
  /** The area the menu hangs in from its end; the button's own box without it */
  getContainer?: () => HTMLElement | undefined;
  /** Offered while the server takes problem reports for the chat */
  onReportProblem?: NoneToVoidFunction;
  /** Offered once the chat has a thread with messages */
  onDelete?: NoneToVoidFunction;
}

type MenuHandler = 'report' | 'delete';

// The menu's end keeps 12 px in from the container's and its top covers the container's last 10 px, as in the design
const MENU_INSET = 12;
const MENU_OVERLAP = 10;

/** The chat's "…" menu, as on mobile: Report a Problem and Delete Chat */
function AgentMenu({
  className, menuClassName, getContainer, onReportProblem, onDelete,
}: OwnProps) {
  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();
  const buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();

  const items = useMemo(() => {
    const result: DropdownItem<MenuHandler>[] = [];
    if (onReportProblem) result.push({ value: 'report', name: 'Report a Problem', icon: <AgentReportIcon /> });
    if (onDelete) {
      result.push({
        value: 'delete', name: 'Delete Chat', fontIcon: 'menu-trash', isDangerous: true, withDelimiter: true,
      });
    }
    return result;
  }, [onDelete, onReportProblem]);

  const handleOpenMenu = useLastCallback(() => {
    const container = getContainer?.() ?? buttonRef.current!;
    const { left, right, bottom } = container.getBoundingClientRect();
    // The menu hangs from the container's end, which is its left one in RTL
    const x = lang.isRtl ? left + MENU_INSET : right - MENU_INSET;
    setMenuAnchor({ x, y: bottom - MENU_OVERLAP });
    openMenu();
  });

  const handleCloseMenuAnimationEnd = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  const handleMenuSelect = useLastCallback((value: MenuHandler) => {
    if (value === 'report') {
      onReportProblem?.();
    } else {
      onDelete?.();
    }
  });

  return (
    <>
      <Button
        ref={buttonRef}
        isSimple
        isText
        kind="transparent"
        className={className}
        ariaLabel={lang('Open Menu')}
        isDisabled={!items.length}
        onClick={handleOpenMenu}
      >
        <i className="icon-menu-dots" aria-hidden />
      </Button>
      {menuAnchor && (
        <DropdownMenu
          ref={menuRef}
          isOpen={isMenuOpen}
          withPortal
          menuAnchor={menuAnchor}
          menuPositionX="right"
          items={items}
          bubbleClassName={menuClassName}
          shouldTranslateOptions
          onSelect={handleMenuSelect}
          onClose={closeMenu}
          onCloseAnimationEnd={handleCloseMenuAnimationEnd}
        />
      )}
    </>
  );
}

export default memo(AgentMenu);
