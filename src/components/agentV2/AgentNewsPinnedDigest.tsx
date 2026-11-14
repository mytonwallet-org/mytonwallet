import React, { memo, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useUniqueId from '../../hooks/useUniqueId';

import Transition from '../ui/Transition';
import AgentNewsPinnedTitle from './AgentNewsPinnedTitle';

import styles from './AgentNewsPinnedDigest.module.scss';

interface OwnProps {
  title: string;
  text: string;
  /** Grows with the digest's delivery time, so a newer digest comes in from below and an older one from above */
  digestKey: number;
  /** The digest's place among the stripe's bars, the oldest first */
  index: number;
  count: number;
  onClick: NoneToVoidFunction;
}

const TRACK_VISIBLE_HEIGHT = 36;
const BAR_SPACING = 2;
const BAR_RADIUS = 1;
const BAR_WIDTH = 2;
const PX_PER_REM = 16;

/**
 * The feed's daily digests as Telegram Web's pinned messages, in a panel attached under the header: a stripe of one bar
 * per digest at the start, the oldest at the top and the shown one lit, the digest's day as the title and its headlines
 * as the text. As the panel shows another digest, the title rolls the characters after the part it keeps and the text
 * slides, both the same way, and the lit bar moves along the stripe, all as in Telegram Web's `HeaderPinnedMessage`.
 */
function AgentNewsPinnedDigest({
  title, text, digestKey, index, count, onClick,
}: OwnProps) {
  const clipPathId = useUniqueId('agentNewsPinnedDigestBars-');
  // The text's slides are keyed by the switch, not by the digest: a digest shown again would find its old slide, which
  // the transition no longer tells apart from the one shown before it
  const slideRef = useRef({ digestKey, key: 0, direction: 1 as 1 | -1 });
  if (slideRef.current.digestKey !== digestKey) {
    slideRef.current = {
      digestKey,
      key: slideRef.current.key + 1,
      direction: digestKey > slideRef.current.digestKey ? 1 : -1,
    };
  }

  return (
    <button
      type="button"
      className={styles.root}
      aria-label={`${title}, ${text}`}
      data-agent-news-pinned-digest
      onClick={onClick}
    >
      <span className={styles.inner} aria-hidden>
        {renderNavigation(index, count, clipPathId)}
        <span className={styles.texts}>
          <span className={styles.title}>
            <AgentNewsPinnedTitle text={title} digestKey={digestKey} />
          </span>
          <span className={styles.textBox}>
            <Transition
              activeKey={slideRef.current.key}
              direction={slideRef.current.direction}
              name="slideVerticalFade"
            >
              <span className={styles.text}>{text}</span>
            </Transition>
          </span>
        </span>
      </span>
    </button>
  );
}

export default memo(AgentNewsPinnedDigest);

/**
 * Telegram Web's `PinnedMessageNavigation`: the bars are cut out of a track by a clip path, the lit one slides over them,
 * and from five bars on the track scrolls to keep the lit one in its 36 px window
 */
function renderNavigation(index: number, count: number, clipPathId: string) {
  if (count === 1) {
    return (
      <span className={styles.navigation}>
        <span className={buildClassName(styles.track, styles.trackSingle)} />
      </span>
    );
  }

  const barHeight = getBarHeight(count);
  const trackHeight = count <= 3 ? TRACK_VISIBLE_HEIGHT : barHeight * count + BAR_SPACING * (count - 1);
  const trackTranslateY = getTrackTranslateY(index, count, barHeight, trackHeight);

  return (
    <span className={styles.navigation}>
      <svg className={styles.clipPathDefs} width="0" height="0">
        <defs>
          <clipPath id={clipPathId}>
            <path d={getClipPathData(count, barHeight)} />
          </clipPath>
        </defs>
      </svg>
      <span
        className={styles.track}
        style={`clip-path: url("#${clipPathId}"); height: ${toRem(trackHeight)}; `
          + `transform: translateY(-${toRem(trackTranslateY)})`}
      >
        <span className={styles.trackBars} />
        <span
          className={styles.mark}
          style={`height: ${toRem(getMarkHeight(count, index))}; `
            + `transform: translateY(${toRem(getMarkTranslateY(index, count, barHeight))})`}
        />
      </span>
    </span>
  );
}

function getBarHeight(count: number) {
  if (count === 2) return 17;
  if (count === 3) return 11;

  return 7.5;
}

function getMarkHeight(count: number, index: number) {
  if (count === 2) return 17;
  if (count === 3) return index === 1 ? 12 : 11;

  return 7.5;
}

function getMarkTranslateY(index: number, count: number, barHeight: number) {
  if (count === 3) return [0, 12, 25][index];

  return (barHeight + BAR_SPACING) * index;
}

function getTrackTranslateY(index: number, count: number, barHeight: number, trackHeight: number) {
  if (count <= 4 || index <= 1) return 0;
  if (index >= count - 2) return trackHeight - TRACK_VISIBLE_HEIGHT;

  return (barHeight + 4) / 2 + (index - 2) * (barHeight + BAR_SPACING);
}

function getClipPathData(count: number, barHeight: number) {
  if (count === 3) {
    return drawBar(0, barHeight) + drawBar(12, barHeight + 1) + drawBar(25, barHeight);
  }

  return Array.from({ length: count }, (_, i) => drawBar((barHeight + BAR_SPACING) * i, barHeight)).join('');
}

function drawBar(y: number, height: number) {
  return `M0,${y + BAR_RADIUS}a${BAR_RADIUS},${BAR_RADIUS},0,0,1,${BAR_WIDTH},0`
    + `v${height - 2 * BAR_RADIUS}a${BAR_RADIUS},${BAR_RADIUS},0,0,1,${-BAR_WIDTH},0Z`;
}

function toRem(px: number) {
  return `${px / PX_PER_REM}rem`;
}
