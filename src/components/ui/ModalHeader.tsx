import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { DropdownItem } from './Dropdown';

import buildClassName from '../../util/buildClassName';
import { getShareIcon } from '../../util/share';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from './Button';
import DropdownMenu from './DropdownMenu';

import modalStyles from './Modal.module.scss';

type OwnProps<T extends string> = {
  title?: string | TeactNode;
  className?: string;
  withNotch?: boolean;
  closeClassName?: string;
  menuItems?: DropdownItem<T>[];
  onClose?: NoneToVoidFunction;
  onBackButtonClick?: NoneToVoidFunction;
  onShareClick?: NoneToVoidFunction;
  onMenuItemClick?: (value: T) => void;
};

function ModalHeader<T extends string>({
  title, className, withNotch, closeClassName, menuItems, onClose, onBackButtonClick, onShareClick, onMenuItemClick,
}: OwnProps<T>) {
  const lang = useLang();

  const menuRef = useRef<HTMLDivElement>();
  const menuButtonRef = useRef<HTMLButtonElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition | undefined>();

  const hasMenu = Boolean(menuItems?.length);
  const isMenuOpen = Boolean(menuAnchor);

  const getTriggerElement = useLastCallback(() => menuButtonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));
  const closeMenu = useLastCallback(() => setMenuAnchor(undefined));

  const handleMenuButtonClick = useLastCallback(() => {
    if (isMenuOpen) {
      closeMenu();
    } else {
      const { right: x, y, height } = menuButtonRef.current!.getBoundingClientRect();
      setMenuAnchor({ x, y: y + height });
    }
  });

  return (
    <div
      className={buildClassName(
        modalStyles.header,
        'with-notch-on-scroll',
        withNotch && 'is-scrolled',
        !onBackButtonClick && modalStyles.header_wideContent,
        className,
        isMenuOpen && 'is-menu-open',
      )}
    >
      {onBackButtonClick && (
        <Button isSimple isText onClick={onBackButtonClick} className={modalStyles.header_back}>
          <i className={buildClassName(modalStyles.header_backIcon, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
      )}
      {onShareClick && !onBackButtonClick && (
        <Button
          isSimple
          isText
          className={modalStyles.header_share}
          ariaLabel={lang('Share Link')}
          onClick={onShareClick}
        >
          <i className={getShareIcon()} aria-hidden />
        </Button>
      )}
      {title !== undefined && (
        <div className={buildClassName(
          modalStyles.title,
          typeof title === 'string' && modalStyles.singleTitle,
          !onBackButtonClick && modalStyles.titleFullWidth,
        )}
        >
          {title}
        </div>
      )}
      {hasMenu && (
        <Button
          ref={menuButtonRef}
          isSimple
          className={buildClassName(modalStyles.menuButton, closeClassName)}
          ariaLabel={lang('Menu')}
          onClick={handleMenuButtonClick}
        >
          <i className={buildClassName(modalStyles.menuIcon, 'icon-menu-dots')} aria-hidden />
        </Button>
      )}
      {onClose && (
        <Button
          isRound
          className={buildClassName(modalStyles.closeButton, closeClassName)}
          ariaLabel={lang('Close')}
          onClick={onClose}
        >
          <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
        </Button>
      )}
      {hasMenu && (
        <DropdownMenu
          isOpen={isMenuOpen}
          ref={menuRef}
          items={menuItems}
          withPortal
          shouldTranslateOptions
          menuPositionX="right"
          menuAnchor={menuAnchor}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={onMenuItemClick}
          onClose={closeMenu}
        />
      )}
    </div>
  );
}

export default memo(ModalHeader);
