import type { ElementRef } from '../../../../../lib/teact/teact';
import { useEffect } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { ApiNftCollection } from '../../../../../api/types';
import { ContentTab } from '../../../../../global/types';

import { captureEvents, SwipeDirection } from '../../../../../util/captureEvents';
import { IS_TOUCH_ENV } from '../../../../../util/windowEnvironment';

import { OPEN_CONTEXT_MENU_CLASS_NAME } from '../Token';

interface SwipeableTab {
  id: ContentTab | number;
}

interface OwnProps {
  transitionRef: ElementRef<HTMLDivElement | undefined>;
  tabs: SwipeableTab[];
  activeTabIndex: number;
  currentCollection?: ApiNftCollection;
  currentSiteCategoryId?: number;
  onSwitchTab: (tab: ContentTab | number) => void;
}

export default function useContentSwipe({
  transitionRef,
  tabs,
  activeTabIndex,
  currentCollection,
  currentSiteCategoryId,
  onSwitchTab,
}: OwnProps) {
  const { closeNftCollection } = getActions();

  useEffect(() => {
    const transitionElement = transitionRef.current;
    if (!IS_TOUCH_ENV || !transitionElement) return undefined;

    return captureEvents(transitionRef.current!, {
      includedClosestSelector: '.swipe-container',
      excludedClosestSelector: '.dapps-feed,.no-swipe',
      onSwipe: (e, direction) => {
        if (
          direction === SwipeDirection.Up
          || direction === SwipeDirection.Down
          // For preventing swipe in one interaction with a long press event handler
          || (e.target as HTMLElement | null)?.closest(`.${OPEN_CONTEXT_MENU_CLASS_NAME}`)
        ) {
          return false;
        }

        // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
        const swipeableTabs = tabs.filter(({ id }) => id !== ContentTab.Settings);
        const swipeableIndex = swipeableTabs.findIndex(({ id }) => id === tabs[activeTabIndex]?.id);
        const currentSwipeIndex = swipeableIndex === -1 ? 0 : swipeableIndex;

        if (direction === SwipeDirection.Left) {
          const tab = swipeableTabs[Math.min(swipeableTabs.length - 1, currentSwipeIndex + 1)];
          onSwitchTab(tab.id);
          return true;
        } else if (direction === SwipeDirection.Right) {
          if (currentSiteCategoryId) return false;

          if (currentCollection) {
            closeNftCollection();
          } else {
            const tab = swipeableTabs[Math.max(0, currentSwipeIndex - 1)];
            onSwitchTab(tab.id);
          }
          return true;
        }

        return false;
      },
      selectorToPreventScroll: '.custom-scroll',
    });
  }, [tabs, onSwitchTab, activeTabIndex, currentCollection, currentSiteCategoryId, transitionRef]);
}
