import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiBaseCurrency, ApiChain, ApiCountryCode, ApiToken } from '../../../api/types';
import type { Account, Theme } from '../../../global/types';

import { CURRENCIES } from '../../../config';
import {
  selectAccount,
  selectAllowedOnOffRampCurrencies,
  selectCurrentAccountTokenBalance,
  selectHasMultipleAccounts,
} from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import isViewAccount from '../../../util/isViewAccount';
import {
  getDefaultRampCurrency, getEffectiveRampCurrencies, getOffRampBaselineCurrencies,
} from '../../../util/ramp-currencies';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { getNativeToken } from '../../../util/tokens';

import useAccountSwitcherScreen, { AccountSwitcherScreen } from '../../../hooks/useAccountSwitcherScreen';
import useAppTheme from '../../../hooks/useAppTheme';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useOffRampUrl from '../hooks/useOffRampUrl';

import AccountSwitcherPill from '../../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../../common/AccountSwitcherSlide';
import Button from '../../ui/Button';
import Dropdown, { type DropdownItem } from '../../ui/Dropdown';
import Modal from '../../ui/Modal';
import Spinner from '../../ui/Spinner';
import Transition from '../../ui/Transition';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './OffRampWidgetModal.module.scss';

interface StateProps {
  chain?: ApiChain;
  address?: string;
  token?: ApiToken;
  balance?: bigint;
  theme: Theme;
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
  baseCurrency: ApiBaseCurrency;
  countryCode?: ApiCountryCode;
  allowedCurrencies?: ApiBaseCurrency[];
}

const ANIMATION_TIMEOUT = 200;

function OffRampWidgetModal({
  chain, address, token, balance, theme, accountId, accountTitle, hasMultipleAccounts, baseCurrency, countryCode,
  allowedCurrencies,
}: StateProps) {
  const {
    closeOffRampWidgetModal,
    showError,
    switchAccount,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const animationTimeoutRef = useRef<number>();
  const [isAnimationInProgress, setIsAnimationInProgress] = useState(true);
  const [isIframeLoading, setIsIframeLoading] = useState(true);
  const supportedCurrencies = useMemo(
    () => new Set(getEffectiveRampCurrencies(getOffRampBaselineCurrencies(chain), allowedCurrencies)),
    [chain, allowedCurrencies],
  );
  const [selectedCurrency, setSelectedCurrency] = useState<ApiBaseCurrency | undefined>(
    getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode),
  );
  const isOpen = Boolean(chain) && Boolean(address);

  const {
    renderingKey, nextKey, updateNextKey, openSelector, closeSelector,
  } = useAccountSwitcherScreen(isOpen, accountId);

  const { url, error, isLoading: isUrlLoading } = useOffRampUrl({
    // Re-checked at build time, not only at dropdown render: the allowed set can shrink while the modal is open
    isOpen: isOpen && Boolean(selectedCurrency && supportedCurrencies.has(selectedCurrency)),
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
      .filter(([currency]) => supportedCurrencies.has(currency as ApiBaseCurrency))
      .map(([currency, { name }]) => ({ value: currency as ApiBaseCurrency, name })),
    [supportedCurrencies],
  );

  useEffect(() => {
    if (isOpen) {
      // Recompute the default once the modal opens with the actual chain (e.g. RUB for RU users on TON)
      setSelectedCurrency(getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode));
    } else {
      setIsAnimationInProgress(true);
      setIsIframeLoading(true);
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
      closeOffRampWidgetModal();
      return;
    }

    if (!selectedCurrency || !supportedCurrencies.has(selectedCurrency)) {
      setSelectedCurrency(getDefaultRampCurrency(supportedCurrencies, baseCurrency, countryCode));
    }
  }, [isOpen, supportedCurrencies, selectedCurrency, baseCurrency, countryCode]);

  // The widget URL is derived from the account address, so a fresh loading cycle is needed after switching
  useEffect(() => {
    window.clearTimeout(animationTimeoutRef.current);
    setIsAnimationInProgress(true);
    setIsIframeLoading(true);
  }, [accountId]);

  useEffect(() => {
    if (error) {
      showError({ error });
      setIsAnimationInProgress(false);
    }
  }, [error, lang, showError]);

  const isLoading = isUrlLoading || isIframeLoading;

  const handleCurrencyChange = useLastCallback((value: ApiBaseCurrency) => {
    window.clearTimeout(animationTimeoutRef.current);
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

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    switchAccount({ accountId: nextAccountId });
  });

  const getIsAccountDisabled = useLastCallback((account: Account) => {
    return isViewAccount(account.type) || !chain || !account.byChain[chain]?.address;
  });

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
        {hasMultipleAccounts && accountId && (
          <AccountSwitcherPill
            accountId={accountId}
            title={accountTitle}
            className={styles.accountPill}
            onClick={openSelector}
          />
        )}
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
            onClose={closeOffRampWidgetModal}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      onClose={closeOffRampWidgetModal}
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
    accountTitle: account?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
    baseCurrency,
    countryCode,
    allowedCurrencies: selectAllowedOnOffRampCurrencies(global),
  };
})(OffRampWidgetModal));
