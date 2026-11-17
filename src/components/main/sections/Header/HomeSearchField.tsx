import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';

import styles from './HomeSearchField.module.scss';

// The search has nothing behind it yet, so the home screen shows the account header in its place
export const IS_HOME_SEARCH_AVAILABLE = false;

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  microphoneRef?: ElementRef<HTMLElement>;
}

function HomeSearchField({ ref, microphoneRef }: OwnProps) {
  const lang = useLang();

  return (
    <div ref={ref} className={styles.root}>
      <i className={buildClassName('icon-search', styles.icon, styles.enlargedIcon)} aria-hidden />
      <span className={styles.placeholder}>{lang('Search or Ask')}</span>
      <i
        ref={microphoneRef}
        className={buildClassName('icon-microphone', styles.icon, styles.enlargedIcon)}
        aria-hidden
      />
    </div>
  );
}

export default memo(HomeSearchField);
