import React, { memo } from '../../lib/teact/teact';

import type { MediaViewerPictureNews } from '../../global/types';
import type { AgentNewsMenuHandler } from '../agent/hooks/useAgentNewsMenu';

import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useAgentNewsMenu from '../agent/hooks/useAgentNewsMenu';

import DropdownMenu from '../ui/DropdownMenu';

import styles from './MediaViewer.module.scss';

interface OwnProps {
  news: MediaViewerPictureNews;
  /** The actions go into a menu, and the close button stands at the start of the header, as on Telegram's phones */
  isMobile: boolean;
  onClose: NoneToVoidFunction;
}

/** A News picture's actions, which are its post's menu, as Telegram's media viewer shows a photo's actions */
function PictureActions({ news, isMobile, onClose }: OwnProps) {
  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const { menuItems, handleMenuItemSelect } = useAgentNewsMenu(news);

  const handleButtonClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    handleMenuItemSelect(e.currentTarget.dataset.action as AgentNewsMenuHandler);
  });

  if (isMobile) {
    return (
      <div className={styles.actions}>
        <button
          type="button"
          aria-label={lang('More actions')}
          aria-haspopup="menu"
          aria-expanded={isMenuOpen}
          className={buildClassName(styles.pictureButton, isMenuOpen && styles.pictureButton_active)}
          onClick={openMenu}
        >
          <i className={buildClassName('icon icon-more', styles.pictureButtonIcon)} aria-hidden />
        </button>
        <DropdownMenu
          isOpen={isMenuOpen}
          items={menuItems}
          menuPositionY="top"
          menuPositionX="right"
          shouldTranslateOptions
          className="component-theme-dark"
          buttonClassName={styles.menuItem}
          onSelect={handleMenuItemSelect}
          onClose={closeMenu}
        />
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.actions, styles.pictureActions)}>
      {menuItems.map(({
        value, name, icon, fontIcon,
      }) => (
        <button
          key={value}
          type="button"
          aria-label={lang(name)}
          data-action={value}
          className={styles.pictureButton}
          onClick={handleButtonClick}
        >
          {fontIcon
            ? <i className={buildClassName('icon', `icon-${fontIcon}`, styles.pictureButtonIcon)} aria-hidden />
            : icon}
        </button>
      ))}
      <button type="button" aria-label={lang('Close')} className={styles.pictureButton} onClick={onClose}>
        <i className={buildClassName('icon icon-close', styles.pictureButtonIcon)} aria-hidden />
      </button>
    </div>
  );
}

export default memo(PictureActions);
