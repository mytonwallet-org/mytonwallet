import React, { memo } from '../../lib/teact/teact';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';

import styles from './Agent.module.scss';

interface OwnProps {
  text: string;
  isRetrying?: boolean;
  onRetry: NoneToVoidFunction;
}

/** A chat or the news feed that has nothing to show after its load failed: why, centered, with Retry under it */
function AgentLoadFailure({ text, isRetrying, onRetry }: OwnProps) {
  const lang = useLang();

  return (
    <div className={styles.loadFailure} role="alert">
      <span>{text}</span>
      <Button isSmall isPrimary className={styles.loadFailureRetry} isLoading={isRetrying} onClick={onRetry}>
        {lang('Retry')}
      </Button>
    </div>
  );
}

export default memo(AgentLoadFailure);
