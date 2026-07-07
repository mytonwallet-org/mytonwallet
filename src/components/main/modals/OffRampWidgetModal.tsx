import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiChain, ApiCountryCode, ApiToken } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { CURRENCIES } from '../../../config';
import { selectAccount, selectCurrentAccountTokenBalance } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getNativeToken } from '../../../util/tokens';

import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useOffRampUrl from '../hooks/useOffRampUrl';

import Button from '../../ui/Button';
import Dropdown, { type DropdownItem } from '../../ui/Dropdown';
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
  baseCurrency: ApiBaseCurrency;
  countryCode?: ApiCountryCode;
}

const ANIMATION_TIMEOUT = 200;
const SUPPORTED_CURRENCIES = new Set<ApiBaseCurrency>(['EUR', 'RUB']);

function OffRampWidgetModal({
  chain, address, token, balance, theme, accountId, baseCurrency, countryCode,
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
  // Avanchange (RUB) sells GRAM, so it is only offered when selling on the TON chain
  const isAvanchangeAllowed = chain === 'ton';
  const [selectedCurrency, setSelectedCurrency] = useState<ApiBaseCurrency>(
    getDefaultOffRampCurrency(baseCurrency, countryCode, isAvanchangeAllowed),
  );
  const isOpen = Boolean(chain) && Boolean(address);

  const { url, error, isLoading: isUrlLoading } = useOffRampUrl({
    isOpen,
    currency: selectedCurrency,
    chain,
    address,
    token,
    balance,
    accountId,
    appTheme,
  });

  const currencyItems = useMemo<DropdownItem<ApiBaseCurrency>[]>(
    () => Object.entries(CURRENCIES)
      .filter(([currency]) => {
        return SUPPORTED_CURRENCIES.has(currency as ApiBaseCurrency)
          && (isAvanchangeAllowed || currency !== 'RUB');
      })
      .map(([currency, { name }]) => ({ value: currency as ApiBaseCurrency, name })),
    [isAvanchangeAllowed],
  );

  useEffect(() => {
    if (isOpen) {
      // Recompute the default once the modal opens with the actual chain (e.g. RUB for RU users on TON)
      setSelectedCurrency(getDefaultOffRampCurrency(baseCurrency, countryCode, isAvanchangeAllowed));
    } else {
      setIsAnimationInProgress(true);
      setIsIframeLoading(true);
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
  }, [isOpen, baseCurrency, countryCode, isAvanchangeAllowed]);

  useEffect(() => {
    if (error) {
      showError({ error });
      setIsAnimationInProgress(false);
    }
  }, [error, lang, showError]);

  const isLoading = isUrlLoading || isIframeLoading;

  const handleCurrencyChange = useLastCallback((value: ApiBaseCurrency) => {
    setIsIframeLoading(true);
    setIsAnimationInProgress(true);
    setSelectedCurrency(value);
  });

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
          <Dropdown<ApiBaseCurrency>
            items={currencyItems}
            selectedValue={selectedCurrency}
            theme="light"
            menuPositionX="left"
            shouldTranslateOptions
            menuClassName={styles.dropdown}
            itemClassName={styles.dropdownValue}
            onChange={handleCurrencyChange}
          />
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
    restrictions: { countryCode },
    settings: { baseCurrency, theme },
  } = global;

  const token = chain ? getNativeToken(chain) : undefined;
  const balance = token?.slug ? selectCurrentAccountTokenBalance(global, token.slug) : undefined;

  return {
    chain,
    address: chain && account?.byChain?.[chain]?.address,
    token,
    balance,
    theme,
    accountId,
    baseCurrency,
    countryCode,
  };
})(OffRampWidgetModal));

function getDefaultOffRampCurrency(
  baseCurrency: ApiBaseCurrency | undefined,
  countryCode: ApiCountryCode | undefined,
  isAvanchangeAllowed: boolean,
): ApiBaseCurrency {
  const fallbackCurrency: ApiBaseCurrency = countryCode === 'RU' && isAvanchangeAllowed ? 'RUB' : 'EUR';

  const preferred = baseCurrency && SUPPORTED_CURRENCIES.has(baseCurrency)
    ? baseCurrency
    : fallbackCurrency;

  return preferred === 'RUB' && !isAvanchangeAllowed ? 'EUR' : preferred;
}
