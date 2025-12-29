import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './MenuItem.module.scss';

type OnClickHandler<T = void> = T extends void
  ? (e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>) => void
  : (e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>, arg: T) => void;

type OwnProps<T = void> = {
  className?: string;
  href?: string;
  children: TeactNode;
  isDestructive?: boolean;
  role?: string;
  isSelected?: boolean;
} & (T extends void ? {
  onClick?: OnClickHandler<void>;
  clickArg?: never;
} : {
  onClick?: OnClickHandler<T>;
  clickArg: T;
});

function MenuItem<T>(props: OwnProps<T>) {
  const {
    className,
    href,
    children,
    onClick,
    clickArg,
    isDestructive,
    role,
    isSelected,
  } = props;

  const handleClick = useLastCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!onClick) {
      e.stopPropagation();
      e.preventDefault();

      return;
    }

    // Type assertion needed because clickArg is guaranteed to be present when T is not void
    (onClick as (e: React.SyntheticEvent, arg?: T) => void)(e, clickArg);
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.code !== 'Enter' && e.code !== 'Space') {
      return;
    }

    if (!onClick) {
      e.stopPropagation();
      e.preventDefault();

      return;
    }

    // Type assertion needed because clickArg is guaranteed to be present when T is not void
    (onClick as (e: React.SyntheticEvent, arg?: T) => void)(e, clickArg);
  });

  const fullClassName = buildClassName(
    styles.menuItem,
    className,
    isDestructive && styles.destructive,
  );

  if (href) {
    return (
      <a href={href} target="_blank" rel="noopener noreferrer" className={fullClassName}>
        {children}
      </a>
    );
  }

  return (
    <div
      role={role || 'button'}
      aria-selected={isSelected}
      tabIndex={isSelected ? 0 : -1}
      className={fullClassName}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
    >
      {children}
    </div>
  );
}

export default MenuItem;
