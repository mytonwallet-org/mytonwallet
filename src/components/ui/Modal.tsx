import type { ElementRef, RefObject, TeactNode } from '../../lib/teact/teact';
import React, {
  beginHeavyAnimation,
  useEffect,
  useLayoutEffect,
  useRef,
} from '../../lib/teact/teact';
import { addExtraClass } from '../../lib/teact/teact-dom';
import { getGlobal } from '../../global';

import { ANIMATION_END_DELAY, IS_EXTENSION, IS_TELEGRAM_APP } from '../../config';
import { selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../util/captureEvents';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getIsSwipeToCloseDisabled } from '../../util/modalSwipeManager';
import { createSignal } from '../../util/signals';
import {
  disableTelegramMiniAppSwipeToClose,
  enableTelegramMiniAppSwipeToClose,
} from '../../util/telegram';
import trapFocus from '../../util/trapFocus';
import { IS_ANDROID, IS_TOUCH_ENV } from '../../util/windowEnvironment';
import windowSize from '../../util/windowSize';

import freezeWhenClosed from '../../hooks/freezeWhenClosed';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useToggleClass from '../../hooks/useToggleClass';

import Button from './Button';
import Portal from './Portal';

import styles from './Modal.module.scss';

type OwnProps = {
  title?: string | TeactNode;
  className?: string;
  dialogClassName?: string;
  titleClassName?: string;
  contentClassName?: string;
  isOpen?: boolean;
  isCompact?: boolean;
  isInAppLock?: boolean;
  forceBottomSheet?: boolean;
  noBackdrop?: boolean;
  noBackdropClose?: boolean;
  header?: any;
  hasCloseButton?: boolean;
  children: TeactNode;
  onClose: NoneToVoidFunction;
  onCloseAnimationEnd?: NoneToVoidFunction;
  onEnter?: NoneToVoidFunction;
  dialogRef?: ElementRef<HTMLDivElement>;
};

export const CLOSE_DURATION = 350;
export const CLOSE_DURATION_PORTRAIT = IS_ANDROID ? 200 : 500;
const SCROLL_CONTENT_CHECK_THRESHOLD_MS = 500;

const [getModalCloseSignal, setModalCloseSignal] = createSignal<number>(Date.now());

// Modal windows are opened based on the `accountId` for which they were called.
// The `Main` component is recreated when an account is changed, so during the transition period,
// two copies of its modal windows exist (within the `Portal`).
// Therefore, it is necessary to mark the outdated window so that it disappears with an animation.
// (see the `.replaced` class in the `Modal.module.scss` file).
const openModalEntries = new Set<{ element: HTMLElement; accountId?: string }>();

export function closeModal() {
  setModalCloseSignal(Date.now());
}

function Modal({
  dialogRef,
  title,
  className,
  dialogClassName,
  titleClassName,
  contentClassName,
  isOpen,
  isCompact,
  forceBottomSheet,
  isInAppLock,
  noBackdrop,
  noBackdropClose,
  header,
  hasCloseButton,
  children,
  onClose: onCloseProp,
  onCloseAnimationEnd,
  onEnter,
}: OwnProps): TeactJsx {
  const onClose = useLastCallback(onCloseProp);

  const lang = useLang();

  const modalRef = useRef<HTMLDivElement>();
  const localDialogRef = useRef<HTMLDivElement>();
  const swipeDownDateRef = useRef<number>();
  const isFirstRenderRef = useRef(true);
  const { isPortrait } = useDeviceScreen();

  dialogRef ||= localDialogRef;
  const animationDuration = (isPortrait ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION) + ANIMATION_END_DELAY;
  const isSlideUp = !isCompact && isPortrait;

  useHistoryBack({ isActive: isOpen, onBack: onClose, shouldIgnoreForTelegram: isCompact });

  useEffect(() => {
    if (!IS_TELEGRAM_APP || !isOpen || isCompact) return undefined;

    disableTelegramMiniAppSwipeToClose();

    return enableTelegramMiniAppSwipeToClose;
  }, [isCompact, isOpen]);

  useEffect(() => {
    if (!isOpen) return undefined;

    return getModalCloseSignal.subscribe(onClose);
  }, [isOpen, onClose]);

  useEffect(
    () => (isOpen ? captureKeyboardListeners({
      onEsc: { handler: onClose, shouldPreventDefault: IS_EXTENSION },
      ...(onEnter && { onEnter }),
    }) : undefined),
    [isOpen, onClose, onEnter],
  );
  useEffect(() => (isOpen && modalRef.current ? trapFocus(modalRef.current) : undefined), [isOpen]);
  useToggleClass({ className: 'is-modal-open', isActive: !isCompact && isOpen });
  // The shared backdrop in `Modal.module.scss` stays visible as long as at least one modal holds this class.
  // Compact modals are excluded — they usually stack on top of a bigger modal, so they paint their own
  // backdrop (`.backdropTint`) that dims the modal beneath them instead of the single shared layer.
  useToggleClass({ className: 'with-modal-backdrop', isActive: isOpen && !noBackdrop && !isCompact });
  useToggleClass({ className: 'with-in-app-lock-backdrop', isActive: isOpen && !noBackdrop && isInAppLock });

  useLayoutEffect(() => (
    isOpen ? beginHeavyAnimation(animationDuration) : undefined
  ), [animationDuration, isOpen]);

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isOpen || !isPortrait || !isSlideUp) {
      return undefined;
    }

    return captureEvents(modalRef.current!, {
      excludedClosestSelector: '.capture-scroll',
      onSwipe: (e: Event, direction: SwipeDirection) => {
        if (direction === SwipeDirection.Down && getCanCloseModal(swipeDownDateRef, e.target as HTMLElement)) {
          onClose();
          return true;
        }

        return false;
      },
    });
  }, [isOpen, isPortrait, isSlideUp, onClose]);

  // Tracks open modals.
  // If a modal is already open at its very first render, it was created by an account switch
  // (`Main` remounts together with its modals). The old copy is still on screen at
  // that moment, so it gets `.replaced` and fades away.
  useLayoutEffect(() => {
    const isOpenOnFirstRender = isOpen && isFirstRenderRef.current;
    isFirstRenderRef.current = false;

    if (!isOpen) return undefined;

    const currentAccountId = selectCurrentAccountId(getGlobal());

    if (isOpenOnFirstRender) {
      for (const { element, accountId } of openModalEntries) {
        if (accountId !== currentAccountId) {
          addExtraClass(element, styles.replaced);
        }
      }
    }

    const entry = { element: modalRef.current!, accountId: currentAccountId };
    openModalEntries.add(entry);

    return () => {
      openModalEntries.delete(entry);
    };
  }, [isOpen]);

  const { shouldRender } = useShowTransition({
    ref: modalRef,
    isOpen,
    onCloseAnimationEnd,
    className: false,
    closeDuration: animationDuration,
    withShouldRender: true,
  });

  if (!shouldRender) {
    return undefined;
  }

  function renderHeader() {
    if (header) {
      return header;
    }

    if (!title) {
      return undefined;
    }

    return (
      <div
        className={buildClassName(styles.header, styles.header_wideContent, !hasCloseButton && styles.header_noClose)}
      >
        <div className={buildClassName(styles.title, styles.singleTitle, titleClassName)}>{title}</div>
        {hasCloseButton && (
          <Button isRound className={styles.closeButton} ariaLabel={lang('Close')} onClick={onClose}>
            <i className={buildClassName(styles.closeIcon, 'icon-close')} aria-hidden />
          </Button>
        )}
      </div>
    );
  }

  const fullClassName = buildClassName(
    styles.modal,
    className,
    isSlideUp && styles.slideUpAnimation,
    isCompact && styles.compact,
    isCompact && 'is-compact-modal',
    forceBottomSheet && styles.forceBottomSheet,
    isInAppLock && styles.inAppLock,
  );

  const contentFullClassName = buildClassName(
    styles.content,
    isCompact && styles.contentCompact,
    'custom-scroll',
    contentClassName,
  );

  return (
    <Portal>
      <div ref={modalRef} className={fullClassName} tabIndex={-1} role="dialog">
        <div className={styles.container}>
          <div
            className={buildClassName(styles.backdrop, isCompact && !noBackdrop && styles.backdropTint)}
            onClick={!noBackdropClose ? onClose : undefined}
          />
          <div
            className={buildClassName(styles.dialog, dialogClassName)}
            ref={dialogRef}
            dir={lang.isRtl ? 'rtl' : 'ltr'}
          >
            {renderHeader()}
            <div className={contentFullClassName}>{children}</div>
          </div>
        </div>
      </div>
    </Portal>
  );
}

export default freezeWhenClosed(Modal);

function getCanCloseModal(lastScrollRef: RefObject<number | undefined>, el?: HTMLElement) {
  if (windowSize.getIsKeyboardVisible() || getIsSwipeToCloseDisabled()) {
    return false;
  }

  const now = Date.now();
  if (lastScrollRef.current && now - lastScrollRef.current < SCROLL_CONTENT_CHECK_THRESHOLD_MS) {
    return false;
  }

  lastScrollRef.current = now;
  const scrollEl = el?.closest('.custom-scroll');

  return !scrollEl || scrollEl.scrollTop === 0;
}
