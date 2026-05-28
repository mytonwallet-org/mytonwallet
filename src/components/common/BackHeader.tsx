import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';

import styles from './BackHeader.module.scss';

interface OwnProps {
  title: string;
  withNotchOnScroll?: boolean;
  isScrolled?: boolean;
  onBackClick: NoneToVoidFunction;
}

function BackHeader({ title, withNotchOnScroll, isScrolled, onBackClick }: OwnProps) {
  const lang = useLang();

  return (
    <div
      className={buildClassName(
        styles.root,
        withNotchOnScroll && 'with-notch-on-scroll',
        isScrolled && 'is-scrolled',
      )}
    >
      <Button
        className={buildClassName(styles.backButton, withNotchOnScroll && styles.backButtonNoPadding)}
        isSimple
        isText
        onClick={onBackClick}
      >
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
        <span>{lang('Back')}</span>
      </Button>
      <h3 className={styles.title}>{title}</h3>
      <div />
    </div>
  );
}

export default memo(BackHeader);
