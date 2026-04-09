import React, { memo, useLayoutEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiTonWalletVersion } from '../../../api/chains/ton/types';
import type { ApiChain, ApiWalletByChain, ApiWalletVariant } from '../../../api/types';
import type { Account } from '../../../global/types';
import type { TabWithProperties } from '../../ui/TabList';

import { IS_CAPACITOR } from '../../../config';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { getChainConfig, getChainTitle, getSupportedChains } from '../../../util/chain';
import { vibrateOnSuccess } from '../../../util/haptics';
import { swapKeysAndValues } from '../../../util/iteratees';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { shortenAddress } from '../../../util/shortenAddress';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';
import TabList from '../../ui/TabList';
import Transition from '../../ui/Transition';
import AddSubwalletModal from './AddSubwalletModal';
import SettingsWalletDerivations from './SettingsWalletDerivations';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

export interface Wallet {
  address: string;
  version: ApiTonWalletVersion;
  totalBalance: string;
  tokens: string[];
  isTestnetSubwalletId?: boolean;
}

export type ChainWalletBalance = {
  totalBalance: string;
  tokens: string;
};

interface OwnProps {
  isActive?: boolean;
  isInsideModal?: boolean;
  currentVersion?: ApiTonWalletVersion;
  accountChains?: Account['byChain'];
  currentWalletBalanceByChain?: Partial<Record<ApiChain, ChainWalletBalance>>;
  onBackClick: NoneToVoidFunction;
}

const enum SLIDES {
  password,
  walletVariants,
}

const variantTabIdByChain = Object.fromEntries(
  getSupportedChains()
    .filter((chain) => getChainConfig(chain).multiWalletSupport)
    .map((chain, index) => [chain, index]),
) as Record<ApiChain, number>;

const chainByVariantTabId = swapKeysAndValues(variantTabIdByChain);

function getVariantChainTabs(
  accountChains: Partial<Record<ApiChain, unknown>>,
  currentTonVersion?: ApiTonWalletVersion,
) {
  const result: TabWithProperties[] = [];

  for (const chain of getSupportedChains()) {
    if (
      !(chain in accountChains)
      || !getChainConfig(chain).multiWalletSupport
      || (chain === 'ton' && currentTonVersion !== 'W5')
    ) {
      continue;
    }

    result.push({
      id: variantTabIdByChain[chain],
      title: getChainTitle(chain),
      className: buildClassName(styles.variantTab, styles[chain]),
    });
  }

  return result;
}

function SettingsWalletVariants({
  isActive,
  isInsideModal,
  currentVersion,
  accountChains,
  currentWalletBalanceByChain,
  onBackClick,
}: OwnProps) {
  const {
    closeSettings,
    addSubWallet,
    createSubWallet,
    setIsPinAccepted,
    showToast,
  } = getActions();
  const lang = useLang();
  const transitionRef = useRef<HTMLDivElement>();

  const [currentSlide, setCurrentSlide] = useState<SLIDES>(
    getHasInMemoryPassword() ? SLIDES.walletVariants : SLIDES.password,
  );
  const [activeChain, setActiveChain] = useState<ApiChain>('ton');

  const [password, setPassword] = useState<string>();
  const [passwordError, setPasswordError] = useState<string>();
  const [selectedDerivationWallet, setSelectedDerivationWallet] = useState<{
    chain: ApiChain;
    newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>;
  }>();

  const derivationsCacheRef = useRef<Partial<Record<ApiChain, ApiWalletVariant<ApiChain>[]>>>({});

  const handleDerivationsLoaded = useLastCallback((chain: ApiChain, results: ApiWalletVariant<ApiChain>[]) => {
    derivationsCacheRef.current[chain] = results;
  });

  const cleanup = useLastCallback(() => {
    setPassword(undefined);
    setPasswordError(undefined);
    derivationsCacheRef.current = {};
  });

  const handleBackToSettingsClick = useLastCallback(() => {
    cleanup();
    onBackClick();
  });

  useLayoutEffect(() => {
    if (isActive && getHasInMemoryPassword()) {
      void getInMemoryPassword().then(setPassword);
    }
  }, [isActive]);

  useHistoryBack({
    isActive,
    onBack: handleBackToSettingsClick,
  });

  const {
    handleScroll,
    isScrolled,
    isAtEnd,
  } = useScrolledState();

  const handleGoToVariants = useLastCallback(() => {
    setCurrentSlide(SLIDES.walletVariants);
  });

  useLayoutEffect(() => {
    if (password === undefined && isActive && !getHasInMemoryPassword()) {
      setCurrentSlide(SLIDES.password);
    } else if (!isActive) cleanup();
  }, [password, isActive]);

  const handlePasswordSubmit = useLastCallback(async (enteredPassword: string) => {
    const result = await callApi('verifyPassword', enteredPassword);

    if (!result) {
      const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
      setPasswordError(error);
      return;
    }

    if (getDoesUsePinPad()) {
      setIsPinAccepted();
      await vibrateOnSuccess(true);
    }

    handleGoToVariants();
    setPassword(enteredPassword);
  });

  const clearPasswordError = useLastCallback(() => {
    setPasswordError(undefined);
  });

  const tabs = useMemo(() => getVariantChainTabs(accountChains ?? {}, currentVersion), [accountChains, currentVersion]);
  const activeTab = variantTabIdByChain[activeChain] ?? 0;

  useLayoutEffect(() => {
    if (tabs.length > 0) {
      setActiveChain((current) => {
        if (tabs.some((tab) => tab.id === variantTabIdByChain[current])) {
          return current;
        }

        return chainByVariantTabId[tabs[0].id] ?? current;
      });
    }
  }, [tabs]);

  const handleSwitchTab = useLastCallback((tabId: number) => {
    const newChain = chainByVariantTabId[tabId];
    if (newChain) {
      setActiveChain(newChain);
    }
  });

  const handleCreateSubwallet = useLastCallback(() => {
    if (!password) return;

    createSubWallet({ chain: activeChain, password });
    closeSettings();
    showToast({ message: lang('Subwallet Created'), icon: 'icon-subwallet-add' });
  });

  const handleDerivationWalletClick = useLastCallback((
    chain: ApiChain,
    newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>,
  ) => {
    setSelectedDerivationWallet({ chain, newWallet });
  });

  const handleCloseAddSubwallet = useLastCallback(() => {
    setSelectedDerivationWallet(undefined);
  });

  const handleConfirmAddSubwallet = useLastCallback((shouldReplace: boolean) => {
    if (selectedDerivationWallet) {
      addSubWallet({
        chain: selectedDerivationWallet.chain,
        newWallet: selectedDerivationWallet.newWallet,
        isReplace: shouldReplace,
      });
      closeSettings();
      showToast({
        message: lang(shouldReplace ? 'Subwallet Switched' : 'Subwallet Added'),
        icon: shouldReplace ? 'icon-subwallet-change' : 'icon-subwallet-add',
      });
    }
    setSelectedDerivationWallet(undefined);
  });

  const chainTabsElement = useMemo(() => (
    <TabList
      tabs={tabs}
      activeTab={activeTab}
      className={styles.variantTabs}
      overlayClassName={buildClassName(styles.variantTabsOverlay, activeChain && styles[activeChain])}
      onSwitchTab={handleSwitchTab}
    />
  ), [tabs, activeTab, activeChain, handleSwitchTab]);

  function renderChainContent(isSlideActive: boolean, _isFrom: boolean, currentKey: number) {
    const chain = chainByVariantTabId[currentKey];
    if (!chain) return undefined;

    const chainWallet = accountChains?.[chain];
    const address = chainWallet?.address ?? '';
    const title = chain === 'ton' ? (currentVersion ?? 'W5')
      : chainWallet?.derivation?.index
        ? `#${chainWallet?.derivation?.index + 1}`
        : '#1';

    const label = chainWallet?.derivation?.label;

    const chainBalance = currentWalletBalanceByChain?.[chain];

    return (
      <>
        <p className={buildClassName(styles.blockTitle, styles.blockTitle_small)}>{lang('Current Wallet')}</p>
        <div className={styles.settingsBlock}>
          <div className={buildClassName(styles.item, styles.item_wallet_no_arrow, styles.item_nonInteractive)}>
            <div className={styles.walletVersionInfo}>
              <div className={styles.walletVariantLabelContainer}>
                <span className={styles.walletVersionTitle}>{title}</span>
                {label && (
                  <span className={styles.walletVariantLabel}>{label}</span>
                )}
              </div>
              <span className={styles.walletVersionAddress}>{shortenAddress(address) ?? ''}</span>
            </div>
            {chainBalance && (
              <div className={styles.walletVersionInfoRight}>
                <span className={styles.walletVersionTokens}>{chainBalance.tokens}</span>
                <span className={styles.walletVersionAmount}>
                  ≈&thinsp;{chainBalance.totalBalance}
                </span>
              </div>
            )}
          </div>
        </div>

        <SettingsWalletDerivations
          isActive={isSlideActive && isActive}
          chain={chain}
          password={password}
          cachedDerivations={derivationsCacheRef.current[chain]}
          onBack={handleBackToSettingsClick}
          onWalletClick={handleDerivationWalletClick}
          onDerivationsLoaded={handleDerivationsLoaded}
        />
      </>
    );
  }

  function renderUnifiedContent() {
    return (
      <div className={styles.slide}>
        <div className={buildClassName(
          isInsideModal ? modalStyles.header : styles.header,
          'with-notch-on-scroll',
          isScrolled && 'is-scrolled',
          isInsideModal && styles.modalHeader,
        )}
        >
          <Button
            isSimple
            isText
            onClick={handleBackToSettingsClick}
            className={isInsideModal ? modalStyles.header_back : styles.headerBack}
          >
            <i
              className={buildClassName(
                isInsideModal ? modalStyles.header_backIcon : styles.iconChevron,
                'icon-chevron-left',
              )}
              aria-hidden
            />
          </Button>
          <div className={isInsideModal ? modalStyles.title : styles.headerTitle}>
            {tabs.length > 1 ? chainTabsElement : lang('$chain_Subwallets', { chain: tabs[0]?.title })}
          </div>
        </div>

        <div className={styles.contentWrapper}>
          <Transition
            activeKey={activeTab}
            name={resolveSlideTransitionName()}
            slideClassName={buildClassName(styles.content, styles.contentWallets, 'custom-scroll')}
            onScroll={handleScroll}
          >
            {renderChainContent}
          </Transition>

          <div className={buildClassName(
            styles.createSubwalletContainer,
            !isAtEnd && styles.createSubwalletWithBorder,
          )}
          >
            <Button
              isPrimary
              onClick={handleCreateSubwallet}
              className={styles.createSubwalletButton}
            >
              <i className={buildClassName('icon-plus', styles.createSubwalletIcon)} aria-hidden />
              {lang('Create Subwallet')}
            </Button>
          </div>
        </div>

        <AddSubwalletModal
          isOpen={!!selectedDerivationWallet}
          onClose={handleCloseAddSubwallet}
          onAdd={handleConfirmAddSubwallet}
        />
      </div>
    );
  }

  function renderContent(isSlideActive: boolean, _isFrom: boolean, _currentKey: number) {
    switch (currentSlide) {
      case SLIDES.password:
        return (
          <div className={styles.slide}>
            {isInsideModal ? (
              <ModalHeader
                title={lang('Confirm Password')}
                onBackButtonClick={handleBackToSettingsClick}
                className={styles.modalHeader}
              />
            ) : (
              <div className={styles.header}>
                <Button isSimple isText onClick={handleBackToSettingsClick} className={styles.headerBack}>
                  <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
                  <span>{lang('Back')}</span>
                </Button>
                <span className={styles.headerTitle}>{lang('Enter Password')}</span>
              </div>
            )}
            <PasswordForm
              isActive={isSlideActive && !!isActive}
              error={passwordError}
              containerClassName={IS_CAPACITOR ? styles.passwordFormContent : styles.passwordFormContentInModal}
              forceBiometricsInMain={!isInsideModal}
              placeholder={lang('Enter your current password')}
              submitLabel={lang('Continue')}
              noAutoConfirm
              onCancel={handleBackToSettingsClick}
              onSubmit={handlePasswordSubmit}
              onUpdate={clearPasswordError}
            />
          </div>
        );

      case SLIDES.walletVariants:
        return renderUnifiedContent();
    }
  }

  return (
    <Transition
      ref={transitionRef}
      name={resolveSlideTransitionName()}
      className={buildClassName(isInsideModal ? modalStyles.transition : styles.transitionContainer, 'custom-scroll')}
      activeKey={currentSlide}
      slideClassName={buildClassName(isInsideModal && modalStyles.transitionSlide)}
      withSwipeControl
    >
      {renderContent}
    </Transition>
  );
}

export default memo(SettingsWalletVariants);
