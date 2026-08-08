import React, {
  memo, useCallback, useEffect, useMemo, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiChain, ApiCountryCode } from '../../../api/types';
import type { Account, Theme } from '../../../global/types';

import { CURRENCIES } from '../../../config';
import {
  selectAccount,
  selectAllowedOnOffRampCurrencies,
  selectCurrentAccountId,
  selectHasMultipleAccounts,
} from '../../../global/selectors';
import { buildAvanchangeUrl } from '../../../util/avanchange';
import buildClassName from '../../../util/buildClassName';
import { mapValues } from '../../../util/iteratees';
import {
  getDefaultRampCurrency, getEffectiveRampCurrencies, getOnRampBaselineCurrencies,
} from '../../../util/ramp-currencies';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { callApi } from '../../../api';
import { getOnRampProvider } from './helpers/onRamp';

import useAccountSwitcherScreen, { AccountSwitcherScreen } from '../../../hooks/useAccountSwitcherScreen';
import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AccountSwitcherPill from '../../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../../common/AccountSwitcherSlide';
import Button from '../../ui/Button';
import Dropdown, { type DropdownItem } from '../../ui/Dropdown';
import Modal from '../../ui/Modal';
import Spinner from '../../ui/Spinner';
import Transition from '../../ui/Transition';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './OnRampWidgetModal.module.scss';

interface StateProps {
  chain?: ApiChain;
  byChain?: Partial<Record<ApiChain, { address: string }>>;
  countryCode?: ApiCountryCode;
  allowedCurrencies?: ApiBaseCurrency[];
  baseCurrency: ApiBaseCurrency;
  theme: Theme;
  currentAccountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
}

const ANIMATION_TIMEOUT = 200;

function OnRampWidgetModal({
  chain, byChain, countryCode, allowedCurrencies, baseCurrency, theme, currentAccountId, accountTitle,
  hasMultipleAccounts,
}: StateProps) {
  const {
    closeOnRampWidgetModal,
    showError,
    switchAccount,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const animationTimeoutRef = useRef<number>();
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [iframeSrc, setIframeSrc] = useState('');
  const supportedCurrencies = useMemo(
    () => new Set(getEffectiveRampCurrencies(getOnRampBaselineCurrencies(chain), allowedCurrencies)),
    [chain, allowedCurrencies],
  );
  const [selectedCurrency, setSelectedCurrency] = useState<ApiBaseCurrency | undefined>(
    getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode),
  );

  // Address of the chain the user opened "Buy" from - used for `isOpen` and the Avanchange URL
  const address = chain ? byChain?.[chain]?.address : undefined;
  const isOpen = Boolean(chain) && Boolean(address);

  const {
    renderingKey, nextKey, updateNextKey, openSelector, closeSelector,
  } = useAccountSwitcherScreen(isOpen, currentAccountId);

  const dropdownItems = useMemo<DropdownItem<ApiBaseCurrency>[]>(
    () => [...supportedCurrencies].map((currency) => ({ value: currency, name: CURRENCIES[currency].name })),
    [supportedCurrencies],
  );

  useEffect(() => {
    if (isOpen) {
      // Recompute the default once the modal opens with the actual chain (e.g. RUB for RU users on TON)
      setSelectedCurrency(getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode));
    } else {
      setIsAnimationInProgress(true);
      setIsLoading(true);
      setIframeSrc('');
    }

    return () => window.clearTimeout(animationTimeoutRef.current);
    // Keyed on the open transition alone. The currency inputs are read here but deliberately left out
    // of the dependencies: a country code that resolves after the modal opened would otherwise replace
    // a currency the user had already picked, and a selection gone invalid is repaired below instead
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [isOpen]);

  // The allowed set can shrink while the modal is open, stranding it on a currency that is no longer offered
  useEffect(() => {
    if (!isOpen) return;

    if (supportedCurrencies.size === 0) {
      closeOnRampWidgetModal();
      return;
    }

    if (!selectedCurrency || !supportedCurrencies.has(selectedCurrency)) {
      setIframeSrc('');
      setSelectedCurrency(getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode));
    }
  }, [isOpen, supportedCurrencies, selectedCurrency, baseCurrency, countryCode]);

  // The widget URL is derived from the account address, so a fresh loading cycle is needed after switching
  useEffect(() => {
    window.clearTimeout(animationTimeoutRef.current);
    setIsAnimationInProgress(true);
    setIsLoading(true);
    setIframeSrc('');
  }, [currentAccountId]);

  const handleError = useLastCallback((error: string) => {
    showError({ error });
    setIsLoading(false);
    setIsAnimationInProgress(false);
  });

  useEffect(() => {
    if (!isOpen || !address) return;

    // Re-checked at build time, not only at dropdown render: the allowed set can shrink while the modal is open
    if (!selectedCurrency || !supportedCurrencies.has(selectedCurrency)) return;

    const provider = getOnRampProvider(chain, selectedCurrency);

    if (provider === 'avanchange') {
      setIframeSrc(buildAvanchangeUrl({
        address,
        give: 'CARDRUB',
        take: 'GRAM',
        type: 'buy',
      }));

      return;
    }

    let isCancelled = false;

    const loadMoonpayCard = async () => {
      try {
        const addressByChain = byChain && mapValues(byChain, (wallet) => wallet.address);

        const response = await callApi('getMoonpayOnrampUrl', {
          chain,
          addressByChain,
          theme: appTheme,
          currency: selectedCurrency,
        });

        // Guard against stale responses when the account, currency or theme changes mid-request
        if (isCancelled) return;

        if (!response || 'error' in response) {
          handleError(response?.error || 'Unknown error');
        } else {
          setIframeSrc(response.url);
        }
      } catch (error) {
        if (isCancelled) return;

        handleError(error instanceof Error ? error.message : String(error));
      }
    };

    void loadMoonpayCard();

    return () => {
      isCancelled = true;
    };
  }, [address, appTheme, byChain, chain, isOpen, lang, selectedCurrency, supportedCurrencies]);

  const handleCardTypeChange = useLastCallback((value: ApiBaseCurrency) => {
    window.clearTimeout(animationTimeoutRef.current);
    setIsLoading(true);
    setIsAnimationInProgress(true);
    setIframeSrc('');
    setSelectedCurrency(value);
  });

  const handleIframeLoad = useCallback(() => {
    setIsLoading(false);

    animationTimeoutRef.current = window.setTimeout(() => {
      setIsAnimationInProgress(false);
    }, ANIMATION_TIMEOUT);
  }, []);

  const handleSelectAccount = useLastCallback((accountId: string) => {
    switchAccount({ accountId });
  });

  const getIsAccountDisabled = useLastCallback((account: Account) => {
    return !chain || !account.byChain[chain]?.address;
  });

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
        {hasMultipleAccounts && currentAccountId && (
          <AccountSwitcherPill
            accountId={currentAccountId}
            title={accountTitle}
            className={styles.accountPill}
            onClick={openSelector}
          />
        )}
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

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: AccountSwitcherScreen) {
    switch (currentKey) {
      case AccountSwitcherScreen.Main:
        return (
          <>
            {renderHeader()}
            <div className={styles.content}>
              {renderLoader()}
              {renderIframe()}
            </div>
          </>
        );
      case AccountSwitcherScreen.Selector:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={closeSelector}
            onClose={closeOnRampWidgetModal}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      onClose={closeOnRampWidgetModal}
      onCloseAnimationEnd={updateNextKey}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const { byChain, title: accountTitle } = selectAccount(global, currentAccountId!) || {};
  const {
    chainForOnRampWidgetModal: chain,
    restrictions: { countryCode },
    settings: { baseCurrency },
  } = global;

  return {
    chain,
    byChain,
    countryCode,
    allowedCurrencies: selectAllowedOnOffRampCurrencies(global),
    baseCurrency,
    theme: global.settings.theme,
    currentAccountId,
    accountTitle,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(OnRampWidgetModal));
