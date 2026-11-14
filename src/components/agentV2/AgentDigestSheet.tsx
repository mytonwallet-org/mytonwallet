import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import type { AgentDigestMinute } from './agentDigestTime';

import buildClassName from '../../util/buildClassName';
import { getAgentDigestTime, setAgentDigestTime, subscribeToAgentDigestTime } from './agentDigestTime';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Modal from '../ui/Modal';
import AgentTimeWheel, { formatDigestTime } from './AgentTimeWheel';

import modalStyles from '../ui/Modal.module.scss';
import styles from './AgentDigestSheet.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
}

/**
 * The daily digest's time, which the feed's settings button opens: in a bottom sheet on a phone and a dialog elsewhere,
 * as the app's other modals. The time's row opens a wheel of hours and minutes under it, as on iOS and Android. A new
 * time brings that time's digests to the feed.
 */
function AgentDigestSheet({ isOpen, onClose }: OwnProps) {
  const lang = useLang();
  const [time, setTime] = useState(getAgentDigestTime);
  const [isTimeWheelOpen, openTimeWheel, closeTimeWheel] = useFlag();

  // The sheet shows the time wherever it is set, as in another window
  useEffect(() => {
    if (!isOpen) return undefined;

    setTime(getAgentDigestTime());
    return subscribeToAgentDigestTime(setTime);
  }, [isOpen]);

  // The sheet opens again with the wheel closed
  useEffect(() => {
    if (!isOpen) closeTimeWheel();
  }, [closeTimeWheel, isOpen]);

  const handleTimeRowClick = useLastCallback(() => {
    if (isTimeWheelOpen) {
      closeTimeWheel();
    } else {
      openTimeWheel();
    }
  });

  // The stored time, rather than the one shown, takes a column's turn, so turns of both columns in one frame add up
  const handleHourChange = useLastCallback((hour: number) => {
    setAgentDigestTime({ ...getAgentDigestTime(), hour });
  });

  const handleMinuteChange = useLastCallback((minute: AgentDigestMinute) => {
    setAgentDigestTime({ ...getAgentDigestTime(), minute });
  });

  return (
    <Modal
      isOpen={isOpen}
      title={lang('$agent_digest_sheet_title')}
      hasCloseButton
      forceBottomSheet
      contentClassName={styles.content}
      onClose={onClose}
    >
      <p className={styles.text}>{lang('$agent_digest_settings_text')}</p>
      <div className={styles.timeSection}>
        <button
          type="button"
          className={styles.timeRow}
          aria-expanded={isTimeWheelOpen}
          onClick={handleTimeRowClick}
        >
          <span className={styles.timeLabel}>{lang('$agent_digest_time')}</span>
          <span className={buildClassName(styles.timeValue, isTimeWheelOpen && styles.timeValueActive)}>
            {formatDigestTime(time)}
          </span>
        </button>
        <AgentTimeWheel
          time={time}
          isOpen={isTimeWheelOpen}
          hourLabel={lang('$agent_digest_hours')}
          minuteLabel={lang('$agent_digest_minutes')}
          onHourChange={handleHourChange}
          onMinuteChange={handleMinuteChange}
        />
      </div>
      <Button isPrimary className={modalStyles.buttonFullWidth} onClick={onClose}>{lang('Done')}</Button>
    </Modal>
  );
}

export default memo(AgentDigestSheet);
