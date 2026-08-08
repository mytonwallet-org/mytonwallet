import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useMemo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import DropdownItemContent from './DropdownItemContent';
import DropdownMenu from './DropdownMenu';
import Spinner from './Spinner';

import styles from './Dropdown.module.scss';

export interface DropdownItem<T extends string = string> {
  value: T;
  name: string;
  selectedName?: string;
  description?: string | TeactNode;
  icon?: string | TeactNode;
  iconClassName?: string;
  overlayIcon?: string;
  fontIcon?: string;
  fontIconClassName?: string;
  isDisabled?: boolean;
  isDangerous?: boolean;
  withDelimiter?: boolean;
  withDelimiterAfter?: boolean;
  noTranslate?: boolean;
}

interface OwnProps<T extends string> {
  label?: string;
  selectedValue?: T;
  items: DropdownItem<T>[];
  className?: string;
  labelClassName?: string;
  itemClassName?: string;
  buttonClassName?: string;
  buttonIconClassName?: string;
  buttonIconOverlayClassName?: string;
  menuClassName?: string;
  theme?: 'light' | 'inherit';
  arrow?: 'caret' | 'chevron' | 'expand';
  menuPositionX?: 'right' | 'left';
  menuPositionY?: 'top' | 'bottom';
  disabled?: boolean;
  shouldTranslateOptions?: boolean;
  onChange?: (value: T) => void;
  isLoading?: boolean;
  buttonPrefix?: TeactNode;
}

const ARROW_ICONS = {
  caret: 'icon-caret-down',
  chevron: 'icon-chevron-down',
  expand: 'icon-expand',
};

const DEFAULT_ARROW = 'caret';
const DEFAULT_MENU_POSITION_X = 'right';

function Dropdown<T extends string>({
  label,
  items,
  selectedValue,
  className,
  labelClassName,
  itemClassName,
  buttonClassName,
  buttonIconClassName,
  buttonIconOverlayClassName,
  menuClassName,
  theme,
  arrow = DEFAULT_ARROW,
  menuPositionX = DEFAULT_MENU_POSITION_X,
  menuPositionY,
  disabled,
  shouldTranslateOptions,
  onChange,
  isLoading = false,
  buttonPrefix,
}: OwnProps<T>): TeactJsx {
  const [isMenuOpen, openMenu, closeMenu] = useFlag();
  const withMenu = items.length > 1;
  const isFullyInteractive = Boolean(label);

  const selectedItem = useMemo<DropdownItem<T>>(() => {
    let item = selectedValue !== undefined && items.find((i) => i.value === selectedValue);
    item ||= { value: '' as T, name: '' };
    return {
      ...item,
      isDisabled: !isFullyInteractive && disabled,
    };
  }, [items, selectedValue, isFullyInteractive, disabled]);

  const handleSelect = useLastCallback((value: T) => {
    if (value !== selectedValue) {
      onChange?.(value);
    }
  });

  if (!items.length) {
    return undefined;
  }

  const fullClassName = buildClassName(
    className,
    withMenu && styles.interactive,
    isFullyInteractive && styles.wide,
    isFullyInteractive && disabled && styles.disabled,
  );
  const buttonFullClassName = buildClassName(
    styles.button,
    withMenu && styles.interactive,
    withMenu && menuClassName,
    theme && styles[theme],
    itemClassName,
    buttonClassName,
  );

  const buttonSuffix = useMemo(() => {
    return withMenu && (
      <i
        className={buildClassName(styles.buttonIcon, ARROW_ICONS[arrow])}
        aria-hidden
      />
    );
  }, [withMenu, arrow]);

  return (
    <div
      className={fullClassName}
      onClick={isFullyInteractive && !disabled && withMenu ? openMenu : undefined}
    >
      {label && <span className={buildClassName(styles.label, labelClassName)}>{label}</span>}

      {isLoading ? (
        <Spinner className={styles.spinner} />
      ) : (
        <DropdownItemContent
          item={selectedItem}
          prefix={buttonPrefix}
          suffix={buttonSuffix}
          shouldTranslate={shouldTranslateOptions}
          shouldUseSelectedName
          className={buttonFullClassName}
          iconClassName={buttonIconClassName}
          iconOverlayClassName={buttonIconOverlayClassName}
          itemClassName={buildClassName('itemName', itemClassName)}
          onClick={!isFullyInteractive && withMenu ? openMenu : undefined}
        />
      )}

      {withMenu && (
        <DropdownMenu
          isOpen={isMenuOpen && !isLoading}
          menuPositionX={menuPositionX}
          menuPositionY={menuPositionY}
          items={items}
          shouldTranslateOptions={shouldTranslateOptions}
          selectedValue={selectedValue}
          buttonClassName={itemClassName}
          onSelect={handleSelect}
          onClose={closeMenu}
        />
      )}
    </div>
  );
}

export default memo(Dropdown);
