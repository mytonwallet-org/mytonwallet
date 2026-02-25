import React, {
  memo, useEffect, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiChain, ApiToken } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { selectAccount, selectCurrentAccountTokenBalance } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getNativeToken } from '../../../util/tokens';

import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useOffRampUrl from '../hooks/useOffRampUrl';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import Spinner from '../../ui/Spinner';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './OffRampWidgetModal.module.scss';

interface StateProps {
  chain?: ApiChain;
  address?: string;
  token?: ApiToken;
  balance?: bigint;
  theme: Theme;
  accountId?: string;
}

const ANIMATION_TIMEOUT = 200;

function OffRampWidgetModal({
  chain, address, token, balance, theme, accountId,
}: StateProps) {
  const {
    closeOffRampWidgetModal,
    showError,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const animationTimeoutRef = useRef<number>();
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isIframeLoading, setIsIframeLoading] = useState(true);
  const isOpen = Boolean(chain) && Boolean(address);

  const { url, error, isLoading: isUrlLoading } = useOffRampUrl({
    isOpen,
    chain,
    address,
    token,
    balance,
    accountId,
    appTheme,
  });

  useEffect(() => {
    if (!isOpen) {
      setIsAnimationInProgress(true);
      setIsIframeLoading(true);
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
  }, [isOpen]);

  useEffect(() => {
    if (error) {
      showError({ error });
      setIsAnimationInProgress(false);
    }
  }, [error, lang, showError]);

  const isLoading = isUrlLoading || isIframeLoading;

  function handleIframeLoad() {
    setIsIframeLoading(false);

    animationTimeoutRef.current = window.setTimeout(() => {
      setIsAnimationInProgress(false);
    }, ANIMATION_TIMEOUT);
  }

  function renderIframe() {
    if (!url) return undefined;

    return (
      <iframe
        title="Off Ramp Widget"
        onLoad={handleIframeLoad}
        className={buildClassName(styles.iframe, !isLoading && styles.fadeIn)}
        width="100%"
        height="100%"
        allow="autoplay; camera; microphone; payment"
        src={url}
      >
        {lang('Cannot load widget')}
      </iframe>
    );
  }

  function renderLoader() {
    return (
      <div className={buildClassName(
        styles.loaderContainer,
        !isLoading && styles.fadeOut,
        !isAnimationInProgress && styles.inactive,
      )}
      >
        <Spinner />
      </div>
    );
  }

  function renderHeader() {
    return (
      <div
        className={buildClassName(modalStyles.header, modalStyles.header_wideContent, styles.header)}
      >
        <div className={buildClassName(modalStyles.title, styles.title)}>
          {lang('Sell on Card')}
        </div>

        <Button
          isRound
          className={buildClassName(modalStyles.closeButton, styles.closeButton)}
          ariaLabel={lang('Close')}
          onClick={closeOffRampWidgetModal}
        >
          <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
        </Button>
      </div>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      header={renderHeader()}
      dialogClassName={styles.modalDialog}
      onClose={closeOffRampWidgetModal}
    >
      <div className={styles.content}>
        {renderLoader()}
        {renderIframe()}
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountId = global.currentAccountId;
  const account = accountId ? selectAccount(global, accountId) : undefined;
  const {
    chainForOffRampWidgetModal: chain,
  } = global;

  const token = chain ? getNativeToken(chain) : undefined;
  const balance = token?.slug ? selectCurrentAccountTokenBalance(global, token.slug) : undefined;

  return {
    chain,
    address: chain && account?.byChain?.[chain]?.address,
    token,
    balance,
    theme: global.settings.theme,
    accountId,
  };
})(OffRampWidgetModal));
