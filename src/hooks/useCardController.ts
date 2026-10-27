import { useMemo, useRef } from '../lib/teact/teact';

import type { CardController, CardMotionFrame } from '../util/card/types';

import useLastCallback from './useLastCallback';

export default function useCardController() {
  const cardRef = useRef<HTMLDivElement>();
  const controller = useMemo<CardController>(() => ({ cardRef }), []);

  const handleMotionFrame = useLastCallback((frame: CardMotionFrame) => {
    controller.motion = frame;
    controller.wakeSurface?.();
  });

  return { cardRef, controller, handleMotionFrame };
}
