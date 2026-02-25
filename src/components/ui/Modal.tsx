import type { ElementRef, RefObject, TeactNode } from '../../lib/teact/teact';
import React, {
  beginHeavyAnimation,
  useEffect,
  useLayoutEffect,
  useRef,
} from '../../lib/teact/teact';

import { ANIMATION_END_DELAY, IS_EXTENSION, IS_TELEGRAM_APP } from '../../config';
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
import useHideBrowser from '../../hooks/useHideBrowser';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useToggleClass from '../../hooks/useToggleClass';

import Button from './Button';
import { getInAppBrowser } from './InAppBrowser';
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
  dialogRef ||= localDialogRef;

  const { isPortrait } = useDeviceScreen();

  useHideBrowser(isOpen, isCompact);

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

  useLayoutEffect(() => (
    isOpen ? beginHeavyAnimation(animationDuration) : undefined
  ), [animationDuration, isOpen]);

  // Make sure to hide browser before presenting modals
  useEffect(() => {
    const browser = getInAppBrowser();
    if (!isOpen) {
      // Before showing browser, make sure that closed modals are updated state properly
      requestAnimationFrame(() => {
        browser?.show();
      });
      return;
    }

    void browser?.hide();
  }, [isOpen]);

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

  const backdropFullClass = buildClassName(styles.backdrop, noBackdrop && styles.noBackdrop);

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
          <div className={backdropFullClass} onClick={!noBackdropClose ? onClose : undefined} />
          <div
            className={buildClassName(styles.dialog, dialogClassName)}
            ref={dialogRef}
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
