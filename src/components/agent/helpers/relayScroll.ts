import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { cancelScrollAnimation, isAnimatingScroll } from '../../../util/animateScroll';
import { animate } from '../../../util/animation';
import { getQuestionSpringProgress, QUESTION_SPRING_DURATION } from './agentMotion';

// A relay that another one starts over ends at once, putting the list and the rows that leave where it ends them
const finishRelays = new WeakMap<HTMLElement, NoneToVoidFunction>();

/** Ends the relay of `element` in this frame's mutations, as a list that is reset no longer shows the rows that leave */
export function finishRelayScroll(element: HTMLElement) {
  if (!finishRelays.has(element)) return;

  requestMutation(() => finishRelays.get(element)?.());
}

/**
 * A scroll to a target more than a screen away as iOS's chat makes it, after Telegram's list: the list is at its target
 * at once, and the rows that were on screen, drawn as they were, slide out by the screen's height as the target's rows
 * slide in after them, on the spring a sent question goes up on. Measures `element` and returns the mutation that
 * starts it, or nothing for a target within a screen, which the caller scrolls to itself.
 */
export function measureRelayScroll(
  element: HTMLElement,
  getTargetScrollTop: (element: HTMLElement) => number,
  onEnd?: NoneToVoidFunction,
): NoneToVoidFunction | undefined {
  const {
    scrollTop, scrollHeight, clientHeight, offsetTop, offsetLeft, offsetWidth, offsetHeight,
  } = element;
  const parent = element.parentElement;
  const maxScrollTop = Math.max(0, scrollHeight - clientHeight);
  const target = Math.round(Math.min(Math.max(getTargetScrollTop(element), 0), maxScrollTop));
  const offset = target - scrollTop;
  // The rows that leave are drawn over the list in its parent, where the list stands
  if (!clientHeight || Math.abs(offset) <= clientHeight || !parent || element.offsetParent !== parent) return undefined;

  const distance = Math.sign(offset) * clientHeight;

  return () => {
    finishRelays.get(element)?.();
    if (isAnimatingScroll(element)) cancelScrollAnimation();

    const departing = element.cloneNode(true) as HTMLElement;
    departing.setAttribute('aria-hidden', 'true');
    departing.setAttribute('inert', '');
    departing.setAttribute('data-agent-departing-rows', '');
    Object.assign(departing.style, {
      position: 'absolute',
      top: `${offsetTop}px`,
      left: `${offsetLeft}px`,
      width: `${offsetWidth}px`,
      height: `${offsetHeight}px`,
      margin: '0',
      overflow: 'hidden',
      pointerEvents: 'none',
    });
    element.after(departing);
    departing.scrollTop = scrollTop;
    element.scrollTop = target;

    const setProgress = (progress: number) => {
      element.style.transform = progress < 1 ? `translateY(${distance * (1 - progress)}px)` : '';
      departing.style.transform = `translateY(${-distance * progress}px)`;
    };
    setProgress(0);

    let isFinished = false;
    const finish = () => {
      if (isFinished) return;
      isFinished = true;
      finishRelays.delete(element);
      setProgress(1);
      departing.remove();
      onEnd?.();
    };
    finishRelays.set(element, finish);

    const startAt = Date.now();
    animate(() => {
      if (isFinished) return false;

      const fraction = Math.min(1, (Date.now() - startAt) / QUESTION_SPRING_DURATION);
      if (fraction >= 1 || !element.isConnected) {
        finish();
        return false;
      }

      setProgress(getQuestionSpringProgress(fraction));
      return true;
    }, requestMutation);
  };
}
