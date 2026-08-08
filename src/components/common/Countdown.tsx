import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import type { LangFn } from '../../hooks/useLang';

import buildClassName from '../../util/buildClassName';
import { SECOND } from '../../util/dateFormat';
import { toNativeDigits } from '../../util/nativeDigits';
import { setCancellableTimeout } from '../../util/schedulers';

import useLang from '../../hooks/useLang';

import styles from './Countdown.module.scss';

interface OwnProps {
  timestamp: number;
  deadline: number;
  onCompleted?: NoneToVoidFunction;
}

const WARNING_TIME = 5 * 60; // 5 minutes in seconds;

function Countdown({
  timestamp,
  deadline,
  onCompleted,
}: OwnProps) {
  const lang = useLang();
  const initialSeconds = Math.floor((timestamp + deadline - Date.now()) / SECOND);
  const [secondsLeft, setSecondsLeft] = useState(Math.max(initialSeconds, 0));
  const shouldShowWarning = secondsLeft <= WARNING_TIME;

  useEffect(() => {
    const clearTimer = setCancellableTimeout(SECOND, () => {
      if (secondsLeft <= 0) return;

      setSecondsLeft(Math.floor((timestamp + deadline - Date.now()) / SECOND));
    });

    if (secondsLeft <= 0) {
      onCompleted?.();
    }

    return clearTimer;
  }, [secondsLeft, onCompleted, timestamp, deadline]);

  return (
    <span className={buildClassName(
      styles.time,
      shouldShowWarning && styles.timeWarning,
    )}
    >
      {formatTime(lang, secondsLeft)}
    </span>
  );
}

function formatTime(lang: LangFn, seconds: number): string {
  const pad = (num: number) => num.toString().padStart(2, '0');

  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;

  let formattedTime = hours > 0 ? `${hours}:` : '';
  formattedTime += `${hours > 0 ? pad(minutes) : minutes}:`;
  formattedTime += pad(remainingSeconds);

  return toNativeDigits(formattedTime);
}

export default memo(Countdown);
