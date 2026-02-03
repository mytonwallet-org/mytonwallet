import type { ElementRef } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import styles from './SuggestionList.module.scss';

export const SUGGESTION_ITEM_CLASS_NAME = styles.suggestion;

interface OwnProps {
  listRef?: ElementRef<HTMLDivElement>;
  position?: 'top' | 'bottom';
  suggestions: string[];
  activeIndex?: number;
  isHidden?: boolean;
  onSelect: (suggest: string) => void;
}

function SuggestionList({
  listRef,
  position = 'bottom',
  suggestions,
  activeIndex,
  isHidden,
  onSelect,
}: OwnProps) {
  const lang = useLang();

  const fullClassName = buildClassName(
    styles.suggestions,
    styles[position],
    isHidden && styles.hidden,
  );

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault();

    const suggest = (e.target as HTMLLIElement).innerText.trim();
    onSelect(suggest);
  };

  return suggestions.length ? (
    <div
      ref={listRef}
      role="listbox"
      aria-hidden={isHidden}
      className={fullClassName}
    >
      {suggestions.map((suggestion, index) => {
        const isActive = index === activeIndex;

        return (
          <div
            key={suggestion}
            tabIndex={0}
            role="option"
            aria-selected={isActive}
            className={buildClassName(styles.suggestion, isActive && styles.active)}
            onMouseDown={handleClick}
          >
            {suggestion}
          </div>
        );
      })}
    </div>
  ) : (
    <div className={styles.suggestions}>
      <div className={styles.suggestion}>{lang('No suggestions, you\'re on your own!')}</div>
    </div>
  );
}

export default memo(SuggestionList);
