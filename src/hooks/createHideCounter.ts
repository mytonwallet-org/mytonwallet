import { useEffect, useState } from '../lib/teact/teact';

import { createCallbackManager } from '../util/callbacks';

// Hides a shared panel, such as the toolbar or the bottom bar, while at least one screen asks to hide it
export default function createHideCounter() {
  let hideCounter = 0;
  const listeners = createCallbackManager();

  function getIsHidden() {
    return hideCounter > 0;
  }

  function hide() {
    const wasHidden = getIsHidden();
    hideCounter += 1;

    if (!wasHidden) listeners.runCallbacks();
  }

  function show() {
    const wasHidden = getIsHidden();
    hideCounter = Math.max(0, hideCounter - 1);

    if (wasHidden && !getIsHidden()) listeners.runCallbacks();
  }

  function useHide(isHidden: boolean) {
    useEffect(() => {
      if (!isHidden) return undefined;

      hide();

      return show;
    }, [isHidden]);
  }

  function useIsHidden() {
    const [isHidden, setIsHidden] = useState(getIsHidden());

    useEffect(() => {
      const unsubscribe = listeners.addCallback(() => {
        setIsHidden(getIsHidden());
      });

      // The effects of child components run first, so a screen mounted together with the subscriber
      // may have asked to hide before this subscription existed
      setIsHidden(getIsHidden());

      return unsubscribe;
    }, []);

    return isHidden;
  }

  return { useHide, useIsHidden };
}
