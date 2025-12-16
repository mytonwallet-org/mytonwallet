import type { FC } from '../../lib/teact/teact';
import React, {
  useEffect, useRef, useState,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Portal from './Portal';

import styles from './Toast.module.scss';

type OwnProps = {
  containerId?: string;
  message: string;
  icon?: string;
  onDismiss: () => void;
};

const DURATION_MS = 5000;
const ANIMATION_DURATION = 250;

const Toast: FC<OwnProps> = ({
  icon, message, containerId, onDismiss,
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
        <div className={styles.content}>
          {icon && <i className={buildClassName(styles.icon, icon)} aria-hidden />}
          {message}
        </div>
      </div>
    </Portal>
  );
};

export default Toast;
