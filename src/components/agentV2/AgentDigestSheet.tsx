import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { IAnchorPosition } from '../../global/types';
import type { Layout } from '../../hooks/useMenuPosition';
import type { DropdownItem } from '../ui/Dropdown';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { toNativeDigits } from '../../util/nativeDigits';
import { getAgentDigestHour, setAgentDigestHour, subscribeToAgentDigestHour } from './agentDigestHour';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import DropdownMenu from '../ui/DropdownMenu';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';
import styles from './AgentDigestSheet.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
}

const HOURS_PER_DAY = 24;

/**
 * The daily digest's hour, which the feed's bell opens: in a bottom sheet on a phone and a dialog elsewhere, as the
 * app's other modals. The hour is chosen from a menu of the day's hours, which opens at the current one. A new hour
 * brings that hour's digests to the feed.
 */
function AgentDigestSheet({ isOpen, onClose }: OwnProps) {
  const lang = useLang();
  const [hour, setHour] = useState(getAgentDigestHour);
  const [isHourMenuOpen, openHourMenu, closeHourMenu] = useFlag();
  const [hourMenuAnchor, setHourMenuAnchor] = useState<IAnchorPosition | undefined>();
  const timeRowRef = useRef<HTMLButtonElement>();
  const hourMenuRef = useRef<HTMLDivElement>();

  // The sheet shows the hour wherever it is set, as in another window
  useEffect(() => {
    if (!isOpen) return undefined;

    setHour(getAgentDigestHour());
    return subscribeToAgentDigestHour(setHour);
  }, [isOpen]);

  // The menu hangs from the row's end, under it or over it, wherever it fits
  const handleTimeRowClick = useLastCallback(() => {
    const { left, right, bottom } = timeRowRef.current!.getBoundingClientRect();
    setHourMenuAnchor({ x: lang.isRtl ? left : right, y: bottom });
    openHourMenu();
  });

  const handleHourMenuCloseAnimationEnd = useLastCallback(() => {
    setHourMenuAnchor(undefined);
  });

  const handleHourSelect = useLastCallback((value: string) => {
    setAgentDigestHour(Number(value));
  });

  // The menu scrolls to the current hour, which shows in the middle of it as it opens. The hours are its items in order.
  useEffect(() => {
    if (!isHourMenuOpen) return;

    requestMeasure(() => {
      const menu = hourMenuRef.current;
      const item = menu?.children[hour];
      if (!menu || !(item instanceof HTMLElement)) return;

      const scrollTop = item.offsetTop - (menu.clientHeight - item.offsetHeight) / 2;
      requestMutation(() => {
        menu.scrollTop = scrollTop;
      });
    });
  }, [hour, isHourMenuOpen]);

  const getTriggerElement = useLastCallback(() => timeRowRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => hourMenuRef.current);
  const getMenuLayout = useLastCallback((): Layout => ({
    withPortal: true,
    doNotCoverTrigger: true,
    preferredPositionX: lang.isRtl ? 'left' : 'right',
  }));

  return (
    <Modal
      isOpen={isOpen}
      title={lang('$agent_digest_sheet_title')}
      forceBottomSheet
      contentClassName={styles.content}
      onClose={onClose}
    >
      <p className={styles.text}>{lang('$agent_digest_settings_text')}</p>
      <button
        ref={timeRowRef}
        type="button"
        className={styles.timeRow}
        aria-expanded={isHourMenuOpen}
        onClick={handleTimeRowClick}
      >
        <span className={styles.timeLabel}>{lang('$agent_digest_time')}</span>
        <span className={styles.timeValue}>{formatDigestHour(hour)}</span>
        <i className={buildClassName(styles.timeArrow, 'icon-caret-down')} aria-hidden />
      </button>
      <p className={styles.timeZone}>{lang('$agent_digest_device_time_zone')}</p>
      <Button isPrimary className={modalStyles.buttonFullWidth} onClick={onClose}>{lang('Done')}</Button>
      {hourMenuAnchor && (
        <DropdownMenu
          ref={hourMenuRef}
          isOpen={isHourMenuOpen}
          withPortal
          items={buildHourItems()}
          selectedValue={String(hour)}
          bubbleClassName={styles.hourMenu}
          menuAnchor={hourMenuAnchor}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getMenuLayout}
          onSelect={handleHourSelect}
          onClose={closeHourMenu}
          onCloseAnimationEnd={handleHourMenuCloseAnimationEnd}
        />
      )}
    </Modal>
  );
}

export default memo(AgentDigestSheet);

function buildHourItems(): DropdownItem[] {
  return Array.from({ length: HOURS_PER_DAY }, (_, hour) => ({ value: String(hour), name: formatDigestHour(hour) }));
}

/** The hour as the clock shows it, "21:00", in the language's digits, as the feed's times are */
function formatDigestHour(hour: number) {
  return toNativeDigits(`${String(hour).padStart(2, '0')}:00`);
}
