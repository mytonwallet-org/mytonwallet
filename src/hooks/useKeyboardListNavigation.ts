import { useRef } from '../lib/teact/teact';
import { useEffect, useState } from '../lib/teact/teact';
import { getGlobal } from '../global';

import { ANIMATION_LEVEL_MIN } from '../config';
import { requestMeasure } from '../lib/fasterdom/fasterdom';
import useLastCallback from './useLastCallback';

const useKeyboardListNavigation = (
  isOpen: boolean,
  onSelectWithEnter?: (index: number) => void,
  itemSelector?: string,
) => {
  const listRef = useRef<HTMLDivElement>();
  const [activeIndex, setActiveIndex] = useState(-1);

  // Scroll active element into view when index changes
  useEffect(() => {
    if (!isOpen || activeIndex < 0 || !listRef.current) {
      return;
    }

    const listEl = listRef.current;

    requestMeasure(() => {
      const elementChildren = Array.from(itemSelector ? listEl.querySelectorAll(itemSelector) : listEl.children);
      const activeElement = elementChildren[activeIndex] as HTMLElement;

      if (activeElement) {
        activeElement.scrollIntoView({
          block: 'nearest',
          inline: 'nearest',
          behavior: getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN ? 'instant' : 'smooth',
        });
      }
    });
  }, [activeIndex, listRef, isOpen, itemSelector]);

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<any>) => {
    const listEl = listRef.current;

    if (!listEl || !isOpen) {
      return;
    }

    if (e.key === 'Enter' && onSelectWithEnter && activeIndex >= 0) {
      e.preventDefault();
      onSelectWithEnter(activeIndex);
      return;
    }

    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') {
      return;
    }

    e.preventDefault();

    const listChildren = Array.from(itemSelector ? listEl.querySelectorAll(itemSelector) : listEl.children);
    const totalItems = listChildren.length;

    if (totalItems === 0) {
      return;
    }

    let newIndex = activeIndex;

    if (e.key === 'ArrowUp') {
      newIndex = activeIndex <= 0 ? totalItems - 1 : activeIndex - 1;
    } else if (e.key === 'ArrowDown') {
      newIndex = activeIndex >= totalItems - 1 ? 0 : activeIndex + 1;
    }

    setActiveIndex(newIndex);
  });

  const resetIndex = useLastCallback(() => {
    setActiveIndex(-1);
  });

  return {
    activeIndex,
    listRef,
    handleKeyDown,
    resetIndex,
  };
};

export default useKeyboardListNavigation;
