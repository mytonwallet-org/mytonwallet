import { getGlobal } from '../../../global';

import { ANIMATION_LEVEL_MIN } from '../../../config';

const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

// Created once: the spinning top asks on every frame
let reducedMotionQueryList: MediaQueryList | undefined;

/** The Agent's motion runs unless the user turned animations off in the app's settings or in the system */
export default function getCanAnimate() {
  reducedMotionQueryList ??= window.matchMedia(REDUCED_MOTION_QUERY);
  return getGlobal().settings.animationLevel !== ANIMATION_LEVEL_MIN && !reducedMotionQueryList.matches;
}
