import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import Spinner from './Spinner';

import styles from './ListItem.module.scss';

interface OwnProps {
  icon?: string;
  /** Replaces the font icon */
  iconContent?: TeactNode;
  label: TeactNode;
  description?: string;
  className?: string;
  testId?: string;
  isLoading?: boolean;
  isTextTruncated?: boolean;
  onClick: NoneToVoidFunction;
}

function ListItem({
  icon,
  iconContent,
  label,
  description,
  className,
  testId,
  isLoading,
  isTextTruncated,
  onClick,
}: OwnProps) {
  const truncatedClassName = isTextTruncated ? styles.truncated : undefined;

  return (
    <button
      type="button"
      className={buildClassName(styles.root, className)}
      data-testid={testId}
      onClick={onClick}
      disabled={isLoading}
    >
      {iconContent ?? <i className={buildClassName(styles.icon, `icon-${icon}`)} aria-hidden />}
      <span className={buildClassName(styles.label, truncatedClassName)}>
        {label}
        {Boolean(description) && (
          <em className={buildClassName(styles.description, truncatedClassName)}>{description}</em>
        )}
      </span>
      {
        isLoading ? (
          <Spinner className={buildClassName(styles.rightItem, styles.spinner)} />
        ) : (
          <i className={buildClassName(styles.rightItem, 'icon-chevron-right')} aria-hidden />
        )
      }
    </button>
  );
}

export default memo(ListItem);
