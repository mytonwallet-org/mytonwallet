import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import { ANIMATION_LEVEL_MAX } from '../../config';
import buildClassName from '../../util/buildClassName';

import usePrevious2 from '../../hooks/usePrevious2';

import styles from './AgentNewsPinnedTitle.module.scss';

interface OwnProps {
  text: string;
  /** Grows with the digest's delivery time, so a newer digest's title rolls in from below and an older one's from above */
  digestKey: number;
}

const ROLL_DURATION = 200;

/**
 * The pinned digest's title, the digest's day, rolled as Telegram Web's `AnimatedCounter` rolls its characters: the part
 * both titles start with, as "November " of November 9 and November 10, stays, and each character after it rolls in the
 * way the digest's text slides in as the old ones roll away the other way
 */
function AgentNewsPinnedTitle({ text, digestKey }: OwnProps) {
  const prevText = usePrevious2(text);
  const prevDigestKey = usePrevious2(digestKey);
  const [settledText, setSettledText] = useState(text);

  useEffect(() => {
    if (text === settledText) return undefined;

    const timeoutId = window.setTimeout(() => setSettledText(text), ROLL_DURATION);

    return () => window.clearTimeout(timeoutId);
  }, [text, settledText]);

  const isRolling = text !== settledText
    && prevText !== undefined
    && getGlobal().settings.animationLevel === ANIMATION_LEVEL_MAX;
  if (!isRolling) {
    return <span className={styles.root}>{text}</span>;
  }

  const kept = getCommonPrefix(text, prevText);
  const isFromBelow = prevDigestKey !== undefined && digestKey > prevDigestKey;

  return (
    <span className={styles.root}>
      {kept}
      <span key={text} className={styles.tail}>
        {renderCharacters(text.slice(kept.length), isFromBelow ? styles.rollInFromBelow : styles.rollInFromAbove)}
        <span className={styles.tailOld}>
          {renderCharacters(prevText.slice(kept.length), isFromBelow ? styles.rollAwayAbove : styles.rollAwayBelow)}
        </span>
      </span>
    </span>
  );
}

export default memo(AgentNewsPinnedTitle);

function renderCharacters(text: string, className: string) {
  return Array.from(text, (character) => (
    <span className={buildClassName(styles.character, className)}>{character}</span>
  ));
}

function getCommonPrefix(text: string, prevText: string) {
  const characters = Array.from(text);
  const prevCharacters = Array.from(prevText);
  let length = 0;
  while (length < characters.length && characters[length] === prevCharacters[length]) {
    length++;
  }

  return characters.slice(0, length).join('');
}
