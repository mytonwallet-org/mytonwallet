import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';

import styles from './Settings.module.scss';

interface OwnProps {
  title?: string;
  isScrolled?: boolean;
  className?: string;
  onBackClick?: NoneToVoidFunction;
}

function SettingsHeader({ title, isScrolled, className, onBackClick }: OwnProps) {
  const lang = useLang();

  return (
    <div
      className={buildClassName(
        styles.header,
        isScrolled !== undefined && 'with-notch-on-scroll',
        isScrolled && 'is-scrolled',
        className,
      )}
    >
      {onBackClick && (
        <Button isSimple isText onClick={onBackClick} className={styles.headerBack}>
          <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
      )}
      {title && <span className={styles.headerTitle}>{title}</span>}
    </div>
  );
}

export default memo(SettingsHeader);
