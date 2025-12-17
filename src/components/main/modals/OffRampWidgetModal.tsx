import React, {
  memo, useEffect, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiChain } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { SELF_UNIVERSAL_HOST_URL } from '../../../config';
import { selectAccount, selectCurrentAccountTokenBalance } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getNativeToken } from '../../../util/tokens';
import { callApi } from '../../../api';

import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import Spinner from '../../ui/Spinner';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './OffRampWidgetModal.module.scss';

interface StateProps {
  chain?: ApiChain;
  address?: string;
  balance?: bigint;
  theme: Theme;
}

const ANIMATION_TIMEOUT = 200;
const SUPPORTED_CURRENCIES: ApiBaseCurrency[] = ['EUR'];

function OffRampWidgetModal({
  chain, address, balance, theme,
}: StateProps) {
  const {
    closeOffRampWidgetModal,
    showError,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const animationTimeoutRef = useRef<number>();
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [iframeSrc, setIframeSrc] = useState('');
  const isOpen = Boolean(chain) && Boolean(address);
  const isOpenRef = useRef(isOpen);
  isOpenRef.current = isOpen;

  useEffect(() => {
    if (!isOpen) {
      setIsAnimationInProgress(true);
      setIsLoading(true);
      setIframeSrc('');
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
  }, [isOpen]);

  const handleError = useLastCallback((error: string) => {
    showError({ error });
    setIsLoading(false);
    setIsAnimationInProgress(false);
  });

  useEffect(() => {
    if (!isOpen || !address || !chain || balance === undefined) return;

    const loadMoonpayUrl = async () => {
      try {
        const response = await callApi(
          'getMoonpayOfframpUrl',
          chain,
          address,
          appTheme,
          SUPPORTED_CURRENCIES[0],
          balance.toString(),
          `${SELF_UNIVERSAL_HOST_URL}/offramp/`,
        );

        // Guard against stale responses
        if (!isOpenRef.current) return;

        if (!response || 'error' in response) {
          handleError(response?.error || 'Unknown error');
        } else {
          setIframeSrc(response.url);
        }
      } catch (error) {
        handleError(error instanceof Error ? error.message : String(error));
      }
    };

    void loadMoonpayUrl();
  }, [address, appTheme, balance, chain, isOpen, lang]);

  function handleIframeLoad() {
    setIsLoading(false);

    animationTimeoutRef.current = window.setTimeout(() => {
      setIsAnimationInProgress(false);
    }, ANIMATION_TIMEOUT);
  }

  function renderIframe() {
    if (!iframeSrc) return undefined;

    return (
      <iframe
        title="Off Ramp Widget"
        onLoad={handleIframeLoad}
        className={buildClassName(styles.iframe, !isLoading && styles.fadeIn)}
        width="100%"
        height="100%"
        frameBorder="none"
        allow="autoplay; camera; microphone; payment"
        src={iframeSrc}
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
      forceFullNative
      header={renderHeader()}
      dialogClassName={styles.modalDialog}
      nativeBottomSheetKey="offramp-widget"
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
  const { byChain } = selectAccount(global, global.currentAccountId!) || {};
  const {
    chainForOffRampWidgetModal: chain,
  } = global;

  const nativeTokenSlug = chain ? getNativeToken(chain).slug : undefined;
  const balance = nativeTokenSlug ? selectCurrentAccountTokenBalance(global, nativeTokenSlug) : undefined;

  return {
    chain,
    address: chain && byChain?.[chain]?.address,
    balance,
    theme: global.settings.theme,
  };
})(OffRampWidgetModal));
