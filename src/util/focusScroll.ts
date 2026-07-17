import { IS_TELEGRAM_APP } from '../config';
import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { IS_ANDROID, IS_IOS } from './windowEnvironment';

const focusScroller = createFocusScroller();

function isFocusable(element: Element): boolean {
  const tagName = element.tagName.toLowerCase();
  return tagName === 'input'
    || tagName === 'textarea'
    || tagName === 'select'
    || element.hasAttribute('contenteditable');
}

/**
 * Implements a custom scroll behavior on input focus. Meets the following goals:
 * - Allow to customize where to scroll the focused element to (via the `data-focus-scroll-position` HTML attribute).
 * - Scroll to show the focused element if it's behind by the virtual keyboard at the moment when it opens.
 * - Scroll to the focused element smoothly whenever possible.
 *
 * Relies on a `scroll-behavior: smooth;` style set in scrollable elements to implement smooth scrolling depending on
 * the animation preferences.
 */
export function initFocusScrollController() {
  if ((IS_IOS || IS_ANDROID) && window.visualViewport) {
    initForVisualViewport();
  }
}

function initForVisualViewport() {
  const { visualViewport } = window;
  let viewportHeight = visualViewport!.height;

  function handleViewportResize() {
    const newHeight = visualViewport!.height;
    const activeElement = document.activeElement;

    // If the viewport height has decreased (the keyboard has opened) and the active element is focusable,
    // we activate the scroller and scroll to the element
    if (newHeight < viewportHeight && activeElement && isFocusable(activeElement)) {
      focusScroller.install();
      scrollToActiveElement();
    } else if (newHeight > viewportHeight) {
      // If the viewport height has increased (the keyboard has closed), we deactivate the scroller
      focusScroller.uninstall();
    }

    // The viewport height is updated for the next comparison
    viewportHeight = newHeight;
  }

  // In the TMA application on iOS, the VisualViewport behaves incorrectly,
  // not taking into account the height of the virtual keyboard. Therefore,
  // the height compensation is performed first (see the `windowSize` file),
  // and then the `handleViewportResize` processing should be executed.
  function delayedViewportResizeHandler() {
    requestMutation(() => {
      requestMeasure(handleViewportResize);
    });
  }

  visualViewport!.addEventListener(
    'resize',
    IS_IOS && IS_TELEGRAM_APP ? delayedViewportResizeHandler : handleViewportResize,
  );
}

function createFocusScroller() {
  let originalFocus: HTMLElement['focus'] | undefined;
  let isProgrammaticFocus = false;

  // Prevents native scroll for all `focus()` calls, because if the element is outside the viewport, `focus()` scrolls
  // the screen instantly to place the element in the middle (we don't want that).
  const patchedFocus: HTMLElement['focus'] = function focus(this: HTMLElement, options) {
    isProgrammaticFocus = true;
    // Does not work on Android, because it doesn't support `preventScroll`
    originalFocus?.call(this, { ...options, preventScroll: true });
  };

  const handleFocus = () => {
    // Because Android doesn't support `preventScroll`, we make the scroll instant to prevent excessive back-and-forth
    // scrolls. Doing it only for programmatic `focus` calls allows to have smooth scrolling when the user focuses the
    // input by tapping it while the keyboard is open.
    scrollToActiveElement(IS_ANDROID && isProgrammaticFocus);
    isProgrammaticFocus = false;
  };

  return {
    install() {
      if (originalFocus) {
        return; // This branch is reached when the scroller is already installed
      }

      originalFocus = HTMLElement.prototype.focus;
      HTMLElement.prototype.focus = patchedFocus;

      window.addEventListener('focusin', handleFocus);
    },
    uninstall() {
      if (!originalFocus) {
        return; // This branch is reached when the scroller is already uninstalled
      }

      HTMLElement.prototype.focus = originalFocus;
      originalFocus = undefined;

      window.removeEventListener('focusin', handleFocus);
    },
  };
}

function scrollToActiveElement(enforceInstantScroll?: boolean) {
  const scrollTarget = document.activeElement;
  if (!scrollTarget) {
    return;
  }
  const scrollPosition = scrollTarget.dataset.focusScrollPosition ?? 'nearest';
  requestMeasure(() => {
    scrollTarget.scrollIntoView({
      block: scrollPosition,
      behavior: enforceInstantScroll ? 'instant' : 'auto',
    });
  });
}
