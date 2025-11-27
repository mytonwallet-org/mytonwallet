import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { DropdownItem } from './Dropdown';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import styles from './Dropdown.module.scss';

interface OwnProps<T extends string> {
  item: DropdownItem<T>;
  shouldUseSelectedName?: boolean;
  shouldTranslate?: boolean;
  prefix?: TeactNode;
  suffix?: TeactNode;
  className?: string;
  iconClassName?: string;
  iconOverlayClassName?: string;
  fontIconClassName?: string;
  itemClassName?: string;
  itemDescriptionClassName?: string;
  onClick?(event: React.MouseEvent<HTMLButtonElement, MouseEvent>, value: T): void;
}

function DropdownItemContent<T extends string>({
  item,
  shouldUseSelectedName,
  shouldTranslate,
  prefix,
  suffix,
  className,
  iconClassName,
  iconOverlayClassName,
  fontIconClassName,
  itemClassName,
  itemDescriptionClassName,
  onClick,
}: OwnProps<T>) {
  const lang = useLang();
  const displayedName = shouldUseSelectedName ? (item.selectedName ?? item.name) : item.name;

  const fullClassName = buildClassName(
    item.isDisabled && styles.disabled,
    item.isDangerous && styles.dangerous,
    className,
  );

  function renderIcon() {
    if (typeof item.icon !== 'string') {
      return item.icon;
    }

    return (
      <span className={buildClassName('icon', styles.itemIcon, iconClassName)}>
        <img src={item.icon} alt="" className={styles.itemMainIcon} />
        {item.overlayIcon && (
          <img
            src={item.overlayIcon}
            alt=""
            className={buildClassName('icon', styles.itemOverlayIcon, iconOverlayClassName)}
          />
        )}
      </span>
    );
  }

  return (
    <button
      type="button"
      className={fullClassName}
      disabled={item.isDisabled}
      onClick={onClick && ((e) => onClick(e, item.value))}
    >
      {prefix}
      {Boolean(item.icon) && renderIcon()}
      {item.fontIcon && (
        <i
          className={buildClassName(
            `icon icon-${item.fontIcon}`,
            styles.fontIcon,
            fontIconClassName,
            item.fontIconClassName,
          )}
          aria-hidden
        />
      )}
      <span className={buildClassName(styles.itemName, itemClassName)}>
        {shouldTranslate ? lang(displayedName) : displayedName}
        {!!item.description && (
          <span className={buildClassName(styles.itemDescription, itemDescriptionClassName)}>
            {shouldTranslate && typeof item.description === 'string'
              ? lang(item.description)
              : item.description}
          </span>
        )}
      </span>
      {suffix}
    </button>
  );
}

export default memo(DropdownItemContent);
