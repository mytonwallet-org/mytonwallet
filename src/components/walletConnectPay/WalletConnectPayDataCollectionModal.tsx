import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import buildClassName from '../../util/buildClassName';
import {
  canEmbedWalletConnectPayCollect,
  checkIsKycUrlAllowed,
  getWalletConnectPayCollectOrigin,
  listenWalletConnectPayDataCollectionMessages,
} from '../../util/walletConnectPay';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Modal from '../ui/Modal';
import Spinner from '../ui/Spinner';

import modalStyles from '../ui/Modal.module.scss';
import styles from './WalletConnectPay.module.scss';

interface StateProps {
  promiseId?: string;
  url?: string;
  isCompleting?: boolean;
}

const ANIMATION_TIMEOUT = 200;

function WalletConnectPayDataCollectionModal({ promiseId, url, isCompleting }: StateProps) {
  const {
    closeWalletConnectPayDataCollection,
    completeWalletConnectPayDataCollection,
    showError,
  } = getActions();

  const lang = useLang();
  const animationTimeoutRef = useRef<number>();
  const iframeRef = useRef<HTMLIFrameElement>();
  const electronCollectRequestRef = useRef(0);
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isIframeLoading, setIsIframeLoading] = useState(true);

  const isOpen = Boolean(promiseId) && (url ? checkIsKycUrlAllowed(url) : false);
  const useIframe = !IS_ELECTRON || canEmbedWalletConnectPayCollect();
  const collectOrigin = url ? getWalletConnectPayCollectOrigin(url) : undefined;
  const isModalOpen = isOpen && (useIframe || isCompleting);

  useEffect(() => {
    if (!isOpen) {
      setIsAnimationInProgress(true);
      setIsIframeLoading(true);
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || !url || useIframe || isCompleting) {
      return undefined;
    }

    const requestId = ++electronCollectRequestRef.current;

    void window.electron?.openWalletConnectPayCollect(url, {
      message: lang('Are you sure you want to cancel the payment?'),
      continueText: lang('Continue'),
      // Not a plain "Cancel": macOS auto-binds Esc to buttons with the system cancel title,
      // which would conflict with cancelId pointing at "Continue"
      cancelText: lang('Cancel Payment'),
    }).then(() => {
      if (requestId !== electronCollectRequestRef.current) {
        return;
      }

      completeWalletConnectPayDataCollection();
    }).catch((error: unknown) => {
      if (requestId !== electronCollectRequestRef.current) {
        return;
      }

      const message = error instanceof Error ? error.message : String(error);
      if (message !== 'Canceled by the user') {
        showError({ error: message });
      }
      closeWalletConnectPayDataCollection();
    });

    return () => {
      electronCollectRequestRef.current += 1;
      void window.electron?.closeWalletConnectPayCollect();
    };
  }, [
    isOpen,
    url,
    useIframe,
    isCompleting,
    lang,
    completeWalletConnectPayDataCollection,
    closeWalletConnectPayDataCollection,
    showError,
  ]);

  useEffect(() => {
    if (!isOpen || !useIframe || isCompleting) {
      return undefined;
    }

    return listenWalletConnectPayDataCollectionMessages(
      collectOrigin,
      {
        onComplete: completeWalletConnectPayDataCollection,
        onError: (error) => {
          showError({ error });
          closeWalletConnectPayDataCollection();
        },
      },
      iframeRef.current?.contentWindow ?? undefined,
    );
  }, [
    isOpen,
    useIframe,
    isCompleting,
    collectOrigin,
    isIframeLoading,
    completeWalletConnectPayDataCollection,
    closeWalletConnectPayDataCollection,
    showError,
  ]);

  const handleIframeLoad = useLastCallback(() => {
    setIsIframeLoading(false);
    animationTimeoutRef.current = window.setTimeout(() => {
      setIsAnimationInProgress(false);
    }, ANIMATION_TIMEOUT);
  });

  // Data collection is already confirmed at this point, so dismissing the modal would not cancel
  // the payment - the password modal would still appear later
  const handleClose = useLastCallback(() => {
    if (isCompleting) {
      return;
    }

    closeWalletConnectPayDataCollection();
  });

  function renderIframe() {
    if (!url || !useIframe || isCompleting) {
      return undefined;
    }

    return (
      <iframe
        ref={iframeRef}
        title="WalletConnect Pay"
        onLoad={handleIframeLoad}
        className={buildClassName(styles.iframe, styles.collectIframe, !isIframeLoading && styles.fadeIn)}
        width="450"
        height="650"
        frameBorder="none"
        allow="autoplay; camera; microphone; payment"
        src={url}
      />
    );
  }

  function renderLoader() {
    const canFade = useIframe && !isCompleting;

    return (
      <div className={buildClassName(
        styles.loaderContainer,
        canFade && !isIframeLoading && styles.fadeOut,
        canFade && !isAnimationInProgress && styles.inactive,
      )}
      >
        <Spinner />
      </div>
    );
  }

  function renderHeader() {
    return (
      <div className={buildClassName(modalStyles.header, modalStyles.header_wideContent, styles.header)}>
        <div className={buildClassName(modalStyles.title, styles.title)}>
          {lang('Payment')}
        </div>
        {!isCompleting && (
          <Button
            isRound
            className={buildClassName(modalStyles.closeButton, styles.closeButton)}
            ariaLabel={lang('Close')}
            onClick={handleClose}
          >
            <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
          </Button>
        )}
      </div>
    );
  }

  if (!isOpen) {
    return undefined;
  }

  return (
    <Modal
      isOpen={isModalOpen}
      header={renderHeader()}
      dialogClassName={buildClassName(styles.modalDialog, styles.collectModalDialog)}
      onClose={handleClose}
    >
      <div className={buildClassName(styles.content, styles.collectContent)}>
        {renderLoader()}
        {renderIframe()}
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const collection = global.walletConnectPayDataCollection;

  return {
    promiseId: collection?.promiseId,
    url: collection?.url,
    isCompleting: collection?.isCompleting,
  };
})(WalletConnectPayDataCollectionModal));
