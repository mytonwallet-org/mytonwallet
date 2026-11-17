import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AccountBalance } from '../../global/selectors';
import type { IAnchorPosition } from '../../global/types';
import type { MenuHandler } from '../main/sections/Actions/helpers/walletMenu';

import getTestId from '../../util/getTestId';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AccountInfo from '../common/AccountInfo';
import { handleWalletMenuItemClick, SETTINGS_WALLET_MENU_ITEMS } from '../main/sections/Actions/helpers/walletMenu';
import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';

import styles from './SettingsWalletHeader.module.scss';

interface OwnProps {
  accountId: string;
  balanceData?: AccountBalance;
  onRemove: (accountId: string) => void;
}

function SettingsWalletHeader({ accountId, balanceData, onRemove }: OwnProps) {
  const { openReceiveModal } = getActions();

  const lang = useLang();
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();

  const handleReceiveClick = useLastCallback(() => {
    openReceiveModal();
  });

  const openMenu = useLastCallback(() => {
    const { left, right, bottom: y } = menuButtonRef.current!.getBoundingClientRect();
    // RTL: mirror the anchor edge
    setMenuAnchor({ x: lang.isRtl ? left : right, y });
  });

  const closeMenu = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  const handleMenuSelect = useLastCallback((value: MenuHandler) => {
    handleWalletMenuItemClick(value, accountId, onRemove);
  });

  return (
    <div className={styles.root}>
      <AccountInfo balanceData={balanceData} />

      <Button
        className={styles.qrButton}
        isSimple
        isText
        ariaLabel={lang('Receive Funds')}
        testId={getTestId('settings_qr_button')}
        onClick={handleReceiveClick}
      >
        <i className="icon-qr-code" aria-hidden />
      </Button>

      <Button
        ref={menuButtonRef}
        className={styles.menuButton}
        isSimple
        isText
        ariaLabel={lang('More')}
        testId={getTestId('settings_more_button')}
        onClick={openMenu}
      >
        <i className="icon-menu-dots" aria-hidden />
      </Button>

      <DropdownMenu
        isOpen={Boolean(menuAnchor)}
        items={SETTINGS_WALLET_MENU_ITEMS}
        menuAnchor={menuAnchor}
        menuPositionX="right"
        shouldTranslateOptions
        withPortal
        onSelect={handleMenuSelect}
        onClose={closeMenu}
      />
    </div>
  );
}

export default memo(SettingsWalletHeader);
