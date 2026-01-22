import { type ElementRef } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import { vibrate } from '../../../../../util/haptics';

import useContextMenuHandlers from '../../../../../hooks/useContextMenuHandlers';
import useLastCallback from '../../../../../hooks/useLastCallback';

export type MenuHandler = 'reorder' | 'rename' | 'customize' | 'remove';

const items: DropdownItem<MenuHandler>[] = [{
  name: 'Reorder',
  fontIcon: 'menu-reorder',
  value: 'reorder',
}, {
  name: 'Rename',
  fontIcon: 'menu-rename',
  value: 'rename',
}, {
  name: 'Customize',
  fontIcon: 'menu-magic',
  value: 'customize',
}, {
  name: 'Remove',
  fontIcon: 'menu-trash',
  value: 'remove',
  isDangerous: true,
}];

function useAccountContextMenu(ref: ElementRef<HTMLElement>, options: {
  isPortrait?: boolean;
  withContextMenu?: boolean;
  accountId: string;
  onReorderClick: NoneToVoidFunction;
  onRenameClick: NoneToVoidFunction;
  onRemoveClick: NoneToVoidFunction;
}) {
  const {
    openCustomizeWalletModal,
    closeAccountSelector,
    switchAccount,
  } = getActions();

  const {
    isPortrait,
    withContextMenu,
    accountId,
    onReorderClick,
    onRenameClick,
    onRemoveClick,
  } = options;

  const {
    isContextMenuOpen, contextMenuAnchor,
    handleBeforeContextMenu, handleContextMenu,
    handleContextMenuClose, handleContextMenuHide,
  } = useContextMenuHandlers({
    elementRef: ref,
    isMenuDisabled: !withContextMenu,
  });

  const isContextMenuShown = contextMenuAnchor !== undefined;

  const handleMenuItemSelect = useLastCallback((value: MenuHandler) => {
    void vibrate();

    switch (value) {
      case 'reorder':
        onReorderClick();
        break;

      case 'rename':
        onRenameClick();
        break;

      case 'customize':
        closeAccountSelector();
        switchAccount({ accountId });
        openCustomizeWalletModal({ returnTo: 'accountSelector' });
        break;

      case 'remove':
        onRemoveClick();
        break;
    }

    handleContextMenuClose();
  });

  return {
    isContextMenuOpen,
    isContextMenuShown,
    contextMenuAnchor,
    items,
    isBackdropRendered: isPortrait && isContextMenuOpen,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
    handleMenuItemSelect,
  };
}

export default useAccountContextMenu;
