import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { DropdownItem } from '../../ui/Dropdown';

import { copyTextToClipboard } from '../../../util/clipboard';
import { openUrl } from '../../../util/openUrl';
import { shortenAddress } from '../../../util/shortenAddress';
import { getExplorerTransactionUrl } from '../../../util/url';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import DropdownMenu from '../../ui/DropdownMenu';
import DetailRow from '../DetailRow';

import styles from './TradeModal.module.scss';

type MenuAction = 'copy' | 'explorer';

interface OwnProps {
  /** The hash of the Arbitrum transaction that moved the USDC */
  hash: string;
}

const MENU_ITEMS: DropdownItem<MenuAction>[] = [
  { value: 'copy', name: 'Copy', fontIcon: 'menu-copy' },
  { value: 'explorer', name: 'Open in Explorer', fontIcon: 'menu-globe' },
];

/** The Transfer ID row, which copies the hash or opens it in the Arbitrum explorer, as on iOS */
function TransferId({ hash }: OwnProps) {
  const { showToast } = getActions();
  const lang = useLang();

  const [isMenuOpen, openMenu, closeMenu] = useFlag();

  const handleSelect = useLastCallback((action: MenuAction) => {
    if (action === 'copy') {
      void copyTextToClipboard(hash);
      showToast({ message: lang('Data Copied'), icon: 'icon-copy' });
      return;
    }

    const url = getExplorerTransactionUrl('arbitrum', { hash });
    if (url) void openUrl(url);
  });

  return (
    <DetailRow
      label={lang('Transfer ID')}
      value={(
        <>
          <button type="button" className={styles.transferId} onClick={openMenu}>
            {shortenAddress(hash)}
          </button>
          <DropdownMenu
            isOpen={isMenuOpen}
            items={MENU_ITEMS}
            shouldTranslateOptions
            menuPositionX="right"
            menuPositionY="bottom"
            onSelect={handleSelect}
            onClose={closeMenu}
          />
        </>
      )}
      valueClassName={styles.transferIdWrapper}
    />
  );
}

export default memo(TransferId);
