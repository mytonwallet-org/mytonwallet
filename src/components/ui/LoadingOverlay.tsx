import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { TransferState } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';
import useTimeout from '../../hooks/useTimeout';

import Button from './Button';
import Portal from './Portal';
import Spinner from './Spinner';

import styles from './LoadingOverlay.module.scss';

type StateProps = {
  isOpen?: boolean;
};

const CLOSE_BUTTON_DELAY_MS = 7000;

function LoadingOverlay({ isOpen }: StateProps) {
  const { closeLoadingOverlay } = getActions();

  const lang = useLang();
  const [shouldShowCloseButton, showCloseButton, hideCloseButton] = useFlag(false);

  const { shouldRender, ref } = useShowTransition({
    isOpen,
    withShouldRender: true,
  });

  useEffect(() => {
    if (!shouldRender) hideCloseButton();
  }, [shouldRender]);

  useTimeout(showCloseButton, shouldRender ? CLOSE_BUTTON_DELAY_MS : undefined, [shouldRender]);

  if (!shouldRender) return undefined;

  return (
    <Portal>
      <div ref={ref} className={styles.root} onClick={() => closeLoadingOverlay()}>
        <Spinner color="white" className={styles.spinner} />
        <Button
          shouldStopPropagation
          className={buildClassName(styles.button, shouldShowCloseButton && styles.shown)}
          onClick={closeLoadingOverlay}
        >
          {lang('Close')}
        </Button>
      </div>
    </Portal>
  );
}

export default memo(withGlobal(
  (global) => {
    const isDpppModalOpen = (
      global.dappConnectRequest?.state !== undefined || global.currentDappTransfer.state !== TransferState.None
    );

    return {
      isOpen: global.isLoadingOverlayOpen && !isDpppModalOpen,
    };
  },
)(LoadingOverlay));
