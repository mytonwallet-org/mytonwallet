import { useEffect, useState } from '../../../lib/teact/teact';

import type { AnimationLevel } from '../../../global/types';

import { ANIMATION_LEVEL_MIN } from '../../../config';

import { useMediaQuery } from '../../../hooks/useMediaQuery';

export default function useShouldAnimateText(animationLevel: AnimationLevel) {
  const [isDocumentVisible, setIsDocumentVisible] = useState(!document.hidden);
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');

  useEffect(() => {
    function handleVisibilityChange() {
      setIsDocumentVisible(!document.hidden);
    }

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, []);

  return animationLevel !== ANIMATION_LEVEL_MIN
    && !hasReducedMotion
    && isDocumentVisible;
}
