import type { FC } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { stopEvent } from '../../util/domEvents';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Portal from './Portal';

import styles from './Toast.module.scss';

type OwnProps = {
  containerId?: string;
  message: string;
  icon?: string;
  actionText?: string;
  onAction?: NoneToVoidFunction;
  onDismiss: NoneToVoidFunction;
};

const DURATION_MS = 5000;
const ANIMATION_DURATION = 250;

const Toast: FC<OwnProps> = ({
  icon, message, containerId, actionText, onAction, onDismiss,
}) => {
  const [isOpen, setIsOpen] = useState(true);
  const timerRef = useRef<number | undefined>();

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

  const hasAction = Boolean(onAction);

  return (
    <Portal
      className={buildClassName(styles.container, IS_ELECTRON && styles.container_electron)}
      containerId={containerId}
    >
      <div
        ref={ref}
        className={styles.toast}
        onClick={closeAndDismiss}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
      >
        <div className={buildClassName(styles.content, hasAction && styles.content_withAction)}>
          {icon && <i className={buildClassName(styles.icon, icon)} aria-hidden />}
          {message}
        </div>
        {hasAction && (
          <button type="button" className={styles.action} onClick={handleActionClick}>
            {actionText}
          </button>
        )}
      </div>
    </Portal>
  );
};

export default memo(Toast);
