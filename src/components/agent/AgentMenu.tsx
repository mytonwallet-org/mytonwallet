import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';

interface OwnProps {
  className?: string;
  onClearChat: NoneToVoidFunction;
}

const MENU_ITEMS: DropdownItem<'clear'>[] = [
  { value: 'clear', name: 'Clear Chat', fontIcon: 'menu-trash', isDangerous: true },
];

function AgentMenu({ className, onClearChat }: OwnProps) {
  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();
  const buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();

  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    preferredPositionX: 'right',
  }));

  const handleOpenMenu = useLastCallback(() => {
    const btn = buttonRef.current!;
    const { right: x, bottom: y } = btn.getBoundingClientRect();
    setMenuAnchor({ x, y });
    openMenu();
  });

  const handleCloseMenuAnimationEnd = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  const handleMenuSelect = useLastCallback((value: 'clear') => {
    if (value === 'clear') {
      onClearChat();
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
          items={MENU_ITEMS}
          shouldTranslateOptions
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={handleMenuSelect}
          onClose={closeMenu}
          onCloseAnimationEnd={handleCloseMenuAnimationEnd}
        />
      )}
    </>
  );
}

export default memo(AgentMenu);
