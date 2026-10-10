import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { isAnimatingScroll, restartScrollAnimation } from '../../util/animateScroll';

const STICK_TO_BOTTOM_THRESHOLD = 16;

export function updateAgentV2InputBarSpacing(
  element: HTMLElement,
  height: number,
  shouldStickToBottom: boolean | (() => boolean),
  layoutElement = element,
  onUpdated?: NoneToVoidFunction,
) {
  requestMeasure(() => {
    const pinnedScrollHeight = resolveShouldStickToBottom(shouldStickToBottom)
      ? element.scrollHeight
      : undefined;

    requestMutation(() => {
      const value = `${height}px`;
      element.style.setProperty('--agent-input-bar-height', value);
      layoutElement.style.setProperty('--agent-input-bar-height', value);
      onUpdated?.();
      requestForcedReflow(() => {
        if (
          pinnedScrollHeight === undefined
          || !resolveShouldStickToBottom(shouldStickToBottom)
        ) {
          return;
        }

        if (isAnimatingScroll(element)) {
          restartScrollAnimation();
          return;
        }

        scrollInstantly(element, pinnedScrollHeight);
        requestAnimationFrame(() => {
          requestMeasure(() => {
            if (
              !element.isConnected
              || !resolveShouldStickToBottom(shouldStickToBottom)
              || !getIsAgentV2ScrolledToBottom(element)
            ) {
              return;
            }

            scrollInstantly(element, element.scrollHeight);
          });
        });
      });
    });
  });
}

export function getIsAgentV2ScrolledToBottom(element: HTMLElement) {
  return element.scrollHeight - element.scrollTop - element.clientHeight <= STICK_TO_BOTTOM_THRESHOLD;
}

function resolveShouldStickToBottom(value: boolean | (() => boolean)) {
  return typeof value === 'function' ? value() : value;
}

function scrollInstantly(element: HTMLElement, top: number) {
  // `.custom-scroll` is smooth by default, so assigning `scrollTop` would animate layout corrections
  element.scrollTo({ top, behavior: 'instant' });
}
