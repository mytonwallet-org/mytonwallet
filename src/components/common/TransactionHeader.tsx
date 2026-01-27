import React, { memo } from '../../lib/teact/teact';

import type { ApiTransactionActivity } from '../../api/types';
import type { AppTheme } from '../../global/types';

import { ANIMATED_STICKER_TINY_ICON_PX } from '../../config';
import { getIsActivityPendingForUser, getTransactionTitle, isScamTransaction } from '../../util/activities';
import buildClassName from '../../util/buildClassName';
import { formatFullDay, formatTime } from '../../util/dateFormat';
import { getShareIcon } from '../../util/share';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';

import modalStyles from '../ui/Modal.module.scss';
import styles from './TransactionHeader.module.scss';

import scamImg from '../../assets/scam.svg';

interface OwnProps {
  isModalOpen?: boolean;
  transaction: ApiTransactionActivity;
  appTheme: AppTheme;
  className?: string;
  onBackClick?: NoneToVoidFunction;
  onShareClick?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function TransactionHeader({
  isModalOpen,
  transaction,
  appTheme,
  className,
  onBackClick,
  onShareClick,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const { status, isIncoming, timestamp } = transaction;

  const isAnyPending = getIsActivityPendingForUser(transaction);
  const titleTense = isAnyPending ? 'present' : status === 'failed' ? 'future' : 'past';
  const iconClock = status === 'pendingTrusted' ? 'iconClock' : 'iconClockOrange';
  const isScam = isScamTransaction(transaction);

  return (
    <div
      className={buildClassName(
        modalStyles.header,
        !onBackClick && modalStyles.header_wideContent,
        className,
      )}
    >
      {onBackClick && (
        <Button isSimple isText onClick={onBackClick} className={modalStyles.header_back}>
          <i className={buildClassName(modalStyles.header_backIcon, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
      )}
      {onShareClick && !onBackClick && (
        <Button
          isSimple
          isText
          className={modalStyles.header_share}
          ariaLabel={lang('Share Link')}
          onClick={onShareClick}
        >
          <i className={getShareIcon()} aria-hidden />
        </Button>
      )}
      <div className={buildClassName(modalStyles.title, styles.modalTitle)}>
        <div className={styles.headerTitle}>
          {getTransactionTitle(transaction, titleTense, lang)}
          {isAnyPending && (
            <AnimatedIconWithPreview
              play={isModalOpen}
              size={ANIMATED_STICKER_TINY_ICON_PX}
              nonInteractive
              noLoop={false}
              tgsUrl={ANIMATED_STICKERS_PATHS[appTheme][iconClock]}
              previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview[iconClock]}
            />
          )}
          {status === 'failed' && (
            <span className={styles.headerTitle__badge}>
              {lang('Failed')}
            </span>
          )}
          {isScam && isIncoming && <img src={scamImg} alt={lang('Scam')} className={styles.scamImage} />}
        </div>
        {!!timestamp && (
          <div className={styles.headerDate}>
            {formatFullDay(lang.code!, timestamp)}, {formatTime(timestamp)}
          </div>
        )}
      </div>
      <Button
        isRound
        className={modalStyles.closeButton}
        ariaLabel={lang('Close')}
        onClick={onClose}
      >
        <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
      </Button>
    </div>
  );
}

export default memo(TransactionHeader);
