import { ANIMATION_LEVEL_MIN } from '../config';
import { useMediaQuery } from './useMediaQuery';

/** Motion effects stand still at the minimum animation level and when the system asks to reduce motion */
export default function useIsMotionDisabled(animationLevel: number) {
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)') ?? false;

  return animationLevel === ANIMATION_LEVEL_MIN || hasReducedMotion;
}
