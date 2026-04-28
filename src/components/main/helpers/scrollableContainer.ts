import { ACTIVE_SLIDE_CLASS_NAME } from '../../ui/Transition';

/** Finds the appropriate scrollable container */
export function getScrollableContainer(
  element: HTMLElement | null | undefined,
  isPortrait?: boolean,
) {
  // eslint-disable-next-line no-null/no-null
  if (!element) return null;
  const selector = getScrollableContainerSelector(isPortrait);

  if (isPortrait) {
    return element.closest(selector);
  } else {
    return element.matches(selector)
      ? element
      : element.querySelector(selector);
  }
}

// In portrait mode, find the parent `.app-slide-content` container, which contains the all app scrollable content
function getScrollableContainerSelector(isPortrait?: boolean) {
  return isPortrait ? '.app-slide-content' : `.custom-scroll.${ACTIVE_SLIDE_CLASS_NAME}`;
}

export function getScrollContainerClosestSelector(isActive?: boolean, isPortrait?: boolean) {
  if (!isActive) return undefined;
  return isPortrait ? '.app-slide-content' : '.custom-scroll';
}
