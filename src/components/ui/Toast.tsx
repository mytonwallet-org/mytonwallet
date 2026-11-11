import type { FC } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { ToastAnimatedIcon } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { stopEvent } from '../../util/domEvents';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import AnimatedIconWithPreview from './AnimatedIconWithPreview';
import Portal from './Portal';

import styles from './Toast.module.scss';

type OwnProps = {
  containerId?: string;
  message: string;
  icon?: string;
  animatedIcon?: ToastAnimatedIcon;
  isPersistent?: boolean;
  actionText?: string;
  onAction?: NoneToVoidFunction;
  onDismiss: NoneToVoidFunction;
};

const DURATION_MS = 5000;
const ANIMATION_DURATION = 250;

const Toast: FC<OwnProps> = ({
  icon, animatedIcon, message, containerId, actionText, onAction, onDismiss,
}) => {
  const [isOpen, setIsOpen] = useState(true);
  const timerRef = useRef<number | undefined>();

  const withAction = Boolean(onAction);

  const { ref } = useShowTransition({ isOpen });

  const closeAndDismiss = useLastCallback(() => {
    setIsOpen(false);
    setTimeout(onDismiss, ANIMATION_DURATION);
  });

  useEffect(() => (isOpen ? captureEscKeyListener(closeAndDismiss) : undefined), [isOpen, closeAndDismiss]);

  useEffect(() => {
    timerRef.current = window.setTimeout(closeAndDismiss, DURATION_MS);

    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = undefined;
      }
    };
  }, [closeAndDismiss]);

  const handleMouseEnter = useLastCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = undefined;
    }
  });

  const handleMouseLeave = useLastCallback(() => {
    timerRef.current = window.setTimeout(closeAndDismiss, DURATION_MS);
  });

  const handleActionClick = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);

    onAction!();
    closeAndDismiss();
  });

  return (
    <Portal
      className={buildClassName(
        styles.container,
        IS_ELECTRON && styles.container_electron,
        withAction && styles.container_withAction,
      )}
      containerId={containerId}
    >
      <div
        ref={ref}
        className={styles.toast}
        onClick={closeAndDismiss}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
      >
        <div className={buildClassName(styles.content, withAction && styles.content_withAction)}>
          {icon && <i className={buildClassName(styles.icon, icon)} aria-hidden />}
          {animatedIcon && (
            <span className={styles.animatedIcon} aria-hidden>
              <span className={styles.animatedIconFrame}>
                <AnimatedIconWithPreview
                  tgsUrl={animatedIcon.tgsUrl}
                  previewUrl={animatedIcon.previewUrl}
                  size={animatedIcon.size}
                  nonInteractive
                  forceOnHeavyAnimation
                />
              </span>
            </span>
          )}
          {message}
        </div>
        {withAction && (
          <button type="button" className={styles.action} onClick={handleActionClick}>
            {actionText}
          </button>
        )}
      </div>
    </Portal>
  );
};

export default memo(Toast);
