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

/**
 * A News picture's actions, which are its post's menu, as Telegram's media viewer shows a photo's actions. On a desktop
 * Sources opens the post's sources in a menu under it.
 */
function PictureActions({ news, isMobile, onClose }: OwnProps) {
  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const [isSourcesMenuOpen, openSourcesMenu, closeSourcesMenu] = useFlag();
  const {
    menuItems, actionItems, sourceItems, handleMenuItemSelect, resetMenu,
  } = useAgentNewsMenu(news, news.locale);

  const handleButtonClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    const action = e.currentTarget.dataset.action as AgentNewsMenuHandler;
    if (action === 'sources') {
      openSourcesMenu();
      return;
    }

    handleMenuItemSelect(action);
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
          onCloseAnimationEnd={resetMenu}
        />
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.actions, styles.pictureActions)}>
      {actionItems.map(({
        value, name, icon, fontIcon,
      }) => {
        const isSources = value === 'sources';
        const button = (
          <button
            key={value}
            type="button"
            aria-label={lang(name)}
            aria-haspopup={isSources ? 'menu' : undefined}
            aria-expanded={isSources ? isSourcesMenuOpen : undefined}
            data-action={value}
            className={buildClassName(
              styles.pictureButton,
              isSources && isSourcesMenuOpen && styles.pictureButton_active,
            )}
            onClick={handleButtonClick}
          >
            {fontIcon
              ? <i className={buildClassName('icon', `icon-${fontIcon}`, styles.pictureButtonIcon)} aria-hidden />
              : icon}
          </button>
        );
        if (!isSources) return button;

        return (
          <div key={value} className={styles.pictureSources}>
            {button}
            <DropdownMenu
              isOpen={isSourcesMenuOpen}
              items={sourceItems}
              menuPositionY="top"
              menuPositionX="right"
              className="component-theme-dark"
              buttonClassName={styles.menuItem}
              onSelect={handleMenuItemSelect}
              onClose={closeSourcesMenu}
            />
          </div>
        );
      })}
      <button type="button" aria-label={lang('Close')} className={styles.pictureButton} onClick={onClose}>
        <i className={buildClassName('icon icon-close', styles.pictureButtonIcon)} aria-hidden />
      </button>
    </div>
  );
}

export default memo(PictureActions);
