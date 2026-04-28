import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';

import Button from '../../../ui/Button';

import styles from './OverviewBackHeader.module.scss';

interface OwnProps {
  title: string;
  onBackClick: NoneToVoidFunction;
}

function OverviewBackHeader({ title, onBackClick }: OwnProps) {
  const lang = useLang();

  return (
    <div className={styles.root}>
      <Button className={styles.backButton} isSimple isText onClick={onBackClick}>
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
        <span>{lang('Back')}</span>
      </Button>
      <h3 className={styles.title}>{title}</h3>
      <div />
    </div>
  );
}

export default memo(OverviewBackHeader);
