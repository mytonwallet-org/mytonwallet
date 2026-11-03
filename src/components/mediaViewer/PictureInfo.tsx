import React, { memo } from '../../lib/teact/teact';

import type { MediaViewerPictureNews } from '../../global/types';

import { getAgentNewsSourceName } from '../agent/helpers/agentNews';
import formatAgentChatDate from '../agent/helpers/formatAgentChatDate';

import useLang from '../../hooks/useLang';

import WalletAvatar from '../ui/WalletAvatar';

import styles from './MediaViewer.module.scss';

interface OwnProps {
  news: MediaViewerPictureNews;
  /** The picture's place among those the viewer pages through, counted from 1 */
  position: number;
  count: number;
  onClick: NoneToVoidFunction;
}

const BULLET = '•';

/**
 * Who a picture comes from and when, where Telegram shows a photo's sender: the news' source with its avatar, then the
 * picture's place among several, and the date and time. A click goes back to the news, as Telegram's goes to the
 * message.
 */
function PictureInfo({
  news, position, count, onClick,
}: OwnProps) {
  const lang = useLang();
  const sourceName = getAgentNewsSourceName(news) ?? lang('News');
  const date = formatAgentChatDate(lang, news.timestamp);
  const subtitle = [
    count > 1 && lang('$agent_wallet_page_indicator', { current: position, total: count }) as string,
    `${date.day}, ${date.time}`,
  ].filter(Boolean).join(` ${BULLET} `);

  return (
    <div className={styles.pictureInfo} onClick={onClick}>
      <WalletAvatar className={styles.pictureInfoAvatar} title={sourceName} accountId={sourceName} />
      <div className={styles.pictureInfoMeta}>
        <div className={styles.pictureInfoTitle} dir="auto">{sourceName}</div>
        <div className={styles.pictureInfoDate} dir="auto">{subtitle}</div>
      </div>
    </div>
  );
}

export default memo(PictureInfo);
