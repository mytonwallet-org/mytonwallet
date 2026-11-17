import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Menu from '../ui/Menu';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  ariaLabel: string;
  /** Font icon class of the button, such as `icon-info` */
  icon: string;
  testId?: string;
  children: (closeMenu: NoneToVoidFunction) => TeactNode;
}

/** A round header button of a trade form together with the dropdown menu it opens under itself */
function TradeHeaderMenu({
  ariaLabel, icon, testId, children,
}: OwnProps) {
  const lang = useLang();

  const buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();
  const [anchor, setAnchor] = useState<IAnchorPosition | undefined>();
  const isOpen = Boolean(anchor);

  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));
  const closeMenu = useLastCallback(() => setAnchor(undefined));

  const handleButtonClick = useLastCallback(() => {
    if (isOpen) {
      closeMenu();
      return;
    }

    const { left, right, y, height } = buttonRef.current!.getBoundingClientRect();
    // In RTL the menu aligns to the left edge of the button
    setAnchor({ x: lang.isRtl ? left : right, y: y + height });
  });

  return (
    <>
      <Button
        ref={buttonRef}
        isRound
        className={styles.headerButton}
        ariaLabel={ariaLabel}
        testId={testId}
        onClick={handleButtonClick}
      >
        <i className={buildClassName(styles.headerIcon, icon)} aria-hidden />
      </Button>
      <Menu
        menuRef={menuRef}
        isOpen={isOpen}
        type="dropdown"
        withPortal
        bubbleClassName={styles.menuBubble}
        anchor={anchor}
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        onClose={closeMenu}
      >
        {children(closeMenu)}
      </Menu>
    </>
  );
}

export default TradeHeaderMenu;
