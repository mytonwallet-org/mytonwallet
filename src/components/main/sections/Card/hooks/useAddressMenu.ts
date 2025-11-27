import type { ElementRef } from '../../../../../lib/teact/teact';
import { useRef, useState } from '../../../../../lib/teact/teact';

import type { IAnchorPosition } from '../../../../../global/types';
import type { Layout } from '../../../../../hooks/useMenuPosition';

import { useDeviceScreen } from '../../../../../hooks/useDeviceScreen';
import useLastCallback from '../../../../../hooks/useLastCallback';

const MOUSE_LEAVE_TIMEOUT = 150;

export default function useAddressMenu(
  ref: ElementRef<HTMLDivElement>,
  menuRef: ElementRef<HTMLDivElement>,
) {
  const { isPortrait } = useDeviceScreen();
  const closeTimeoutRef = useRef<number | undefined>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isMenuOpen = Boolean(menuAnchor);

  const clearCloseTimeout = useLastCallback(() => {
    if (!closeTimeoutRef.current) return;

    clearTimeout(closeTimeoutRef.current);
    closeTimeoutRef.current = undefined;
  });

  const openMenu = useLastCallback(() => {
    clearCloseTimeout();

    if (!ref.current) return;

    const { left, width, bottom: y } = ref.current.getBoundingClientRect();
    setMenuAnchor({ x: left + width / 2, y });
  });

  const closeMenu = useLastCallback(() => {
    clearCloseTimeout();
    setMenuAnchor(undefined);
  });

  const handleMouseEnter = useLastCallback(() => {
    clearCloseTimeout();
    openMenu();
  });

  const handleMouseLeave = useLastCallback(() => {
    clearCloseTimeout();
    closeTimeoutRef.current = window.setTimeout(closeMenu, MOUSE_LEAVE_TIMEOUT);
  });

  const getTriggerElement = useLastCallback(() => ref.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    isCenteredHorizontally: isPortrait,
    preferredPositionX: 'left' as const,
    doNotCoverTrigger: isPortrait,
  }));

  return {
    menuAnchor,
    isMenuOpen,
    openMenu,
    closeMenu,
    clearCloseTimeout,
    getTriggerElement,
    getRootElement,
    getMenuElement,
    getLayout,
    handleMouseEnter,
    handleMouseLeave,
  };
}
