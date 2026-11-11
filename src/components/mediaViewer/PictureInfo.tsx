import React, { memo } from '../../lib/teact/teact';

import type { MediaViewerPictureNews } from '../../global/types';

import formatAgentChatDate from '../agent/helpers/formatAgentChatDate';

import useLang from '../../hooks/useLang';

import styles from './MediaViewer.module.scss';

interface OwnProps {
  news: MediaViewerPictureNews;
  /** The picture's place among those the viewer pages through, counted from 1 */
  position: number;
  count: number;
  onClick: NoneToVoidFunction;
}

/**
 * Where Telegram shows a photo's sender: the picture's place among several over its date and time, or the date and
 * time alone for a single picture. A click goes back to the news, as Telegram's goes to the message.
 */
function PictureInfo({
  news, position, count, onClick,
}: OwnProps) {
  const lang = useLang();
  const date = formatAgentChatDate(lang, news.timestamp);
  const dateText = `${date.day}, ${date.time}`;
  const hasCounter = count > 1;

  return (
    <div className={styles.pictureInfo} onClick={onClick}>
      <div className={styles.pictureInfoMeta}>
        <div className={styles.pictureInfoTitle} dir="auto">
          {hasCounter ? lang('$agent_wallet_page_indicator', { current: position, total: count }) : dateText}
        </div>
        {hasCounter && <div className={styles.pictureInfoDate} dir="auto">{dateText}</div>}
      </div>
    </div>
  );
}

export default memo(PictureInfo);
