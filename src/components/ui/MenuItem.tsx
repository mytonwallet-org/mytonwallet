import type { FC, TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './MenuItem.module.scss';

type OnClickHandler = (e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>, arg?: any) => void;

interface OwnProps {
  className?: string;
  href?: string;
  children: TeactNode;
  onClick?: OnClickHandler;
  clickArg?: string;
  isDestructive?: boolean;
  role?: string;
  isSelected?: boolean;
}

const MenuItem: FC<OwnProps> = (props) => {
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

    onClick(e, clickArg);
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

    onClick(e);
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
};

export default MenuItem;
