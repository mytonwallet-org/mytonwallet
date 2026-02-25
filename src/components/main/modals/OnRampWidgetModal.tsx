import React, {
  memo, useCallback, useEffect, useMemo, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiChain, ApiCountryCode } from '../../../api/types';
import type { Theme } from '../../../global/types';

import { CURRENCIES } from '../../../config';
import { selectAccount, selectCurrentAccountId } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { callApi } from '../../../api';

import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Dropdown, { type DropdownItem } from '../../ui/Dropdown';
import Modal from '../../ui/Modal';
import Spinner from '../../ui/Spinner';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './OnRampWidgetModal.module.scss';

interface StateProps {
  chain?: ApiChain;
  address?: string;
  countryCode?: ApiCountryCode;
  baseCurrency: ApiBaseCurrency;
  theme: Theme;
}

type CardType = 'avanchange' | 'moonpay';

const ANIMATION_TIMEOUT = 200;
// eslint-disable-next-line @stylistic/max-len
const AVANCHANGE_URL_TEMPLATE = 'https://dreamwalkers.io/ru/mytonwallet/?wallet={address}&give=CARDRUB&take=TON&type=buy';
const SUPPORTED_CURRENCIES = new Set<ApiBaseCurrency>(['USD', 'EUR', 'RUB']);

function OnRampWidgetModal({
  chain, address, countryCode, baseCurrency, theme,
}: StateProps) {
  const {
    closeOnRampWidgetModal,
    showError,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const animationTimeoutRef = useRef<number>();
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [iframeSrc, setIframeSrc] = useState('');
  const [selectedCurrency, setSelectedCurrency] = useState<ApiBaseCurrency>(
    getDefaultCardCurrency(baseCurrency, countryCode),
  );

  const isOpen = Boolean(chain) && Boolean(address);

  const dropdownItems = useMemo<DropdownItem<ApiBaseCurrency>[]>(
    () => Object.entries(CURRENCIES)
      .filter(([currency]) => {
        return SUPPORTED_CURRENCIES.has(currency as ApiBaseCurrency) && (chain !== 'tron' || currency !== 'RUB');
      })
      .map(([currency, { name }]) => ({ value: currency as ApiBaseCurrency, name })),
    [chain],
  );

  useEffect(() => {
    if (!isOpen) {
      setIsAnimationInProgress(true);
      setIsLoading(true);
      setIframeSrc('');
      setSelectedCurrency(getDefaultCardCurrency(baseCurrency, countryCode));
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
  }, [isOpen, countryCode, baseCurrency]);

  const handleError = useLastCallback((error: string) => {
    showError({ error });
    setIsLoading(false);
    setIsAnimationInProgress(false);
  });

  useEffect(() => {
    if (!isOpen || !address) return;

    const currencyAtStart = selectedCurrency;
    const cardType = getCardType(chain, selectedCurrency);

    if (cardType === 'avanchange') {
      setIframeSrc(buildAvanchangeUrl(address));

      return;
    }

    const loadMoonpayCard = async () => {
      try {
        const response = await callApi('getMoonpayOnrampUrl', {
          chain,
          address,
          theme: appTheme,
          currency: selectedCurrency,
        });

        // Guard against stale responses
        if (!isOpen || selectedCurrency !== currencyAtStart) return;

        if (!response || 'error' in response) {
          handleError(response?.error || 'Unknown error');
        } else {
          setIframeSrc(response.url);
        }
      } catch (error) {
        handleError(error instanceof Error ? error.message : String(error));
      }
    };

    void loadMoonpayCard();
  }, [address, appTheme, chain, isOpen, lang, selectedCurrency]);

  const handleCardTypeChange = useLastCallback((value: ApiBaseCurrency) => {
    setIsLoading(true);
    setIsAnimationInProgress(true);
    setSelectedCurrency(value);
  });

  const handleIframeLoad = useCallback(() => {
    setIsLoading(false);

    animationTimeoutRef.current = window.setTimeout(() => {
      setIsAnimationInProgress(false);
    }, ANIMATION_TIMEOUT);
  }, []);

  function renderIframe() {
    if (!iframeSrc) return undefined;

    return (
      <iframe
        title="On Ramp Widget"
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
          {lang('Buy with Card')}
          <Dropdown<ApiBaseCurrency>
            items={dropdownItems}
            selectedValue={selectedCurrency}
            theme="light"
            menuPositionX="left"
            shouldTranslateOptions
            menuClassName={styles.dropdown}
            itemClassName={styles.dropdownValue}
            onChange={handleCardTypeChange}
          />
        </div>

        <Button
          isRound
          className={buildClassName(modalStyles.closeButton, styles.closeButton)}
          ariaLabel={lang('Close')}
          onClick={closeOnRampWidgetModal}
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
      onClose={closeOnRampWidgetModal}
    >
      <div className={styles.content}>
        {renderLoader()}
        {renderIframe()}
      </div>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { byChain } = selectAccount(global, selectCurrentAccountId(global)!) || {};
  const {
    chainForOnRampWidgetModal: chain,
    restrictions: { countryCode },
    settings: { baseCurrency },
  } = global;

  return {
    chain,
    address: chain && byChain?.[chain]?.address,
    countryCode,
    baseCurrency,
    theme: global.settings.theme,
  };
})(OnRampWidgetModal));

function getDefaultCardCurrency(baseCurrency?: ApiBaseCurrency, countryCode?: ApiCountryCode): ApiBaseCurrency {
  const fallbackCurrency: ApiBaseCurrency = countryCode === 'RU' ? 'RUB' : 'USD';

  return baseCurrency && SUPPORTED_CURRENCIES.has(baseCurrency)
    ? baseCurrency
    : fallbackCurrency;
}

function getCardType(chain: ApiChain, currency: ApiBaseCurrency): CardType {
  return currency === 'RUB' ? 'avanchange' : 'moonpay';
}

function buildAvanchangeUrl(address: string): string {
  return AVANCHANGE_URL_TEMPLATE.replace('{address}', encodeURIComponent(address));
}
