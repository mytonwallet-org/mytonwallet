import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';

import styles from './Futures.module.scss';

interface OwnProps {
  className?: string;
  onRetry: NoneToVoidFunction;
}

function LoadError({ className, onRetry }: OwnProps) {
  const lang = useLang();

  // The button passes its click event, which must not reach an action as its payload
  const handleRetryClick = useLastCallback(() => {
    onRetry();
  });

  return (
    <div className={buildClassName(styles.loadError, className)}>
      <p className={styles.loadErrorTitle}>{lang('Failed to Load')}</p>
      <Button isSmall isText className={styles.loadErrorButton} onClick={handleRetryClick}>
        {lang('Try Again')}
      </Button>
    </div>
  );
}

export default memo(LoadError);
