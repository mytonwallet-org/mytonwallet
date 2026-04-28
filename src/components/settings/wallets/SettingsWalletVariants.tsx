import type { TeactNode } from '../../../lib/teact/teact';
import React, { memo, useEffect, useLayoutEffect, useMemo, useState } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiTonWalletVersion } from '../../../api/chains/ton/types';
import type { ApiBaseCurrency, ApiGroupedWalletVariant } from '../../../api/types';
import type { Account, AccountChain, UserToken } from '../../../global/types';

import { IS_CAPACITOR } from '../../../config';
import { selectCurrentAccountId, selectCurrentAccountTokens } from '../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import { getDoesUsePinPad } from '../../../util/biometrics';
import buildClassName from '../../../util/buildClassName';
import { getChainConfig, getOrderedAccountChains } from '../../../util/chain';
import { toBig, toDecimal } from '../../../util/decimals';
import { formatAccountAddresses } from '../../../util/formatAccountAddress';
import { formatCurrency, getShortCurrencySymbol } from '../../../util/formatNumber';
import { vibrateOnSuccess } from '../../../util/haptics';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';
import { pause } from '../../../util/schedulers';
import { callApi } from '../../../api';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Button from '../../ui/Button';
import MenuItem from '../../ui/MenuItem';
import PasswordForm from '../../ui/PasswordForm';
import Spinner from '../../ui/Spinner';
import Transition from '../../ui/Transition';
import SettingsHeader from '../SettingsHeader';

import styles from '../Settings.module.scss';

export interface Wallet {
  address: string;
  version: ApiTonWalletVersion;
  totalBalance: string;
  tokens: string[];
  isTestnetSubwalletId?: boolean;
}

interface OwnProps {
  isActive?: boolean;
  accountChains?: Account['byChain'];
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  accountId: string;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
}

type SubwalletGroup = {
  title: string;
  label?: string;
  addressContent?: TeactNode;
  nativeAmounts: string;
  totalBalance: string;
};

const SEARCH_PAUSE = 5_000;
const MAX_EMPTY_RESULTS_IN_ROW = 5;

const enum SLIDES {
  password,
  walletVariants,
}

function SettingsWalletVariants({
  isActive,
  accountChains,
  onBackClick,
  accountId,
  tokens,
  baseCurrency,
}: OwnProps & StateProps) {
  const {
    closeSettings,
    addSubWallet,
    createSubWallet,
    setIsPinAccepted,
    showToast,
  } = getActions();
  const lang = useLang();

  const [currentSlide, setCurrentSlide] = useState<SLIDES>(
    getHasInMemoryPassword() ? SLIDES.walletVariants : SLIDES.password,
  );

  const [password, setPassword] = useState<string>();
  const [passwordError, setPasswordError] = useState<string>();
  const [groups, setGroups] = useState<ApiGroupedWalletVariant[]>([]);
  const [derivationsError, setDerivationsError] = useState<string>();
  const [isLoadingDerivations, setIsLoadingDerivations] = useState(true);

  const cleanup = useLastCallback(() => {
    setPassword(undefined);
    setPasswordError(undefined);
    setGroups([]);
    setDerivationsError(undefined);
    setIsLoadingDerivations(true);
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

  useEffect(() => {
    if (!isActive || !password) return undefined;

    const currentAccountId = accountId;
    const currentPassword = password;
    let isCancelled = false;

    setDerivationsError(undefined);
    setGroups([]);
    setIsLoadingDerivations(true);

    const runSearch = async () => {
      const mnemonicResult = await callApi('fetchMnemonic', currentAccountId, currentPassword);

      if (!mnemonicResult) {
        setDerivationsError('Unexpected error');
        return;
      }

      let page = 0;
      let emptyResultCounter = 0;
      const knownIndices = new Set<number>();

      try {
        while (!isCancelled) {
          const derivationsResult = await callApi(
            'getWalletVariants',
            currentAccountId,
            page,
            mnemonicResult,
          );

          if (!derivationsResult || 'error' in derivationsResult) {
            if (!isCancelled) {
              setDerivationsError(derivationsResult?.error ?? 'Unexpected error');
            }
            break;
          }

          if (isCancelled) break;

          const newItems = derivationsResult.filter((item) => !knownIndices.has(item.index));
          const hasPositiveBalance = derivationsResult.some((item) =>
            Object.values(item.byChain).some((e) => e && e.balance > 0n));

          if (newItems.length > 0) {
            newItems.forEach((item) => knownIndices.add(item.index));
            setGroups((prev) => prev.concat(newItems));
          }

          emptyResultCounter = hasPositiveBalance ? 0 : emptyResultCounter + 1;
          page += 1;

          if (isCancelled || emptyResultCounter >= MAX_EMPTY_RESULTS_IN_ROW) break;

          await pause(SEARCH_PAUSE);
        }
      } finally {
        if (!isCancelled) {
          setIsLoadingDerivations(false);
        }
      }
    };

    void runSearch();

    return () => {
      isCancelled = true;
    };
  }, [accountId, isActive, password]);

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

  const displayChains = useMemo(
    () => getOrderedAccountChains(accountChains ?? {}),
    [accountChains],
  );

  function renderSubwalletGroupContent(group: SubwalletGroup) {
    return (
      <>
        <div className={styles.walletVersionInfo}>
          <div className={styles.walletVariantLabelContainer}>
            <span className={styles.walletVersionTitle}>{group.title}</span>
            {group.label && (
              <span className={styles.walletVariantLabel}>{group.label}</span>
            )}
          </div>
          {Boolean(group.addressContent) && (
            <span className={styles.walletVersionAddress}>{group.addressContent}</span>
          )}
        </div>
        <div className={styles.walletVersionInfoRight}>
          <span className={styles.walletVersionTokens}>≥&thinsp;{group.totalBalance}</span>
          <span className={styles.walletVersionAmount} title={group.nativeAmounts}>{group.nativeAmounts}</span>
        </div>
      </>
    );
  }

  function buildSubwalletGroup(group: ApiGroupedWalletVariant): SubwalletGroup {
    const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
    const nativeParts: string[] = [];
    let fiatAccum = toBig(0);
    const walletsByChain: Account['byChain'] = {};
    const orderedChains = getOrderedAccountChains(group.byChain);

    for (const chain of orderedChains) {
      const entry = group.byChain[chain];

      if (!entry) continue;

      const accountChain: AccountChain = { address: entry.wallet.address };
      if (entry.wallet.derivation) accountChain.derivation = entry.wallet.derivation;
      walletsByChain[chain] = accountChain;

      const nativeToken = tokens?.find(({ slug }) => slug === getChainConfig(chain).nativeToken?.slug);

      nativeParts.push(formatCurrency(toDecimal(entry.balance, nativeToken?.decimals), nativeToken?.symbol ?? ''));

      fiatAccum = fiatAccum.add(
        toBig(entry.balance, nativeToken?.decimals).mul(nativeToken?.price ?? 0),
      );
    }

    let label: string | undefined;
    for (const chain of orderedChains) {
      const derivation = group.byChain[chain]?.wallet.derivation;
      if (derivation) {
        label = derivation.label;
        break;
      }
    }

    return {
      title: `#${group.index + 1}`,
      label,
      addressContent: formatAccountAddresses(walletsByChain, 'small'),
      nativeAmounts: nativeParts.join(', '),
      totalBalance: formatCurrency(fiatAccum, shortBaseSymbol),
    };
  }

  const currentSubwalletRowModel = useMemo((): SubwalletGroup => {
    const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

    let rowIndex = 0;
    let label: string | undefined;
    for (const chain of displayChains) {
      const derivation = accountChains?.[chain]?.derivation;
      if (typeof derivation?.index === 'number') {
        rowIndex = derivation.index;
        label = derivation.label;
        break;
      }
    }

    const nativeParts: string[] = [];
    let fiatAccum = toBig(0);

    for (const chain of displayChains) {
      const nativeToken = tokens?.find(({ slug }) => slug === getChainConfig(chain).nativeToken?.slug);
      if (nativeToken) {
        nativeParts.push(
          formatCurrency(toDecimal(nativeToken.amount, nativeToken.decimals), nativeToken.symbol),
        );
        fiatAccum = fiatAccum.add(
          toBig(nativeToken.amount, nativeToken.decimals).mul(nativeToken.price ?? 0),
        );
      }
    }

    return {
      title: `#${rowIndex + 1}`,
      label,
      addressContent: accountChains && formatAccountAddresses(accountChains, 'small'),
      nativeAmounts: nativeParts.join(', '),
      totalBalance: formatCurrency(fiatAccum, shortBaseSymbol),
    };
  }, [displayChains, accountChains, tokens, baseCurrency]);

  const handleCreateSubwallet = useLastCallback(() => {
    if (!password) return;

    createSubWallet({ password });
    closeSettings();
    showToast({ message: lang('Subwallet Created'), icon: 'icon-subwallet-add' });
  });

  const handleGroupClick = useLastCallback((
    _e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    group: ApiGroupedWalletVariant,
  ) => {
    addSubWallet({ group });
    closeSettings();
  });

  const hasWallets = groups.length > 0;

  function renderCurrentWalletBlock() {
    return (
      <>
        <p className={buildClassName(styles.blockTitle, styles.blockTitle_small)}>{lang('Current Wallet')}</p>
        <div className={styles.settingsBlock}>
          <div
            className={buildClassName(styles.item, styles.item_wallet_no_arrow, styles.item_nonInteractive)}
          >
            {renderSubwalletGroupContent(currentSubwalletRowModel)}
          </div>
        </div>
      </>
    );
  }

  function renderSubwalletList() {
    return (
      <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
        {groups.map((group) => {
          const rowModel = buildSubwalletGroup(group);

          return (
            <MenuItem<ApiGroupedWalletVariant>
              key={group.index}
              ignoreBaseClassName
              className={buildClassName(styles.item, styles.item_wallet_no_arrow)}
              onClick={handleGroupClick}
              clickArg={group}
            >
              {renderSubwalletGroupContent(rowModel)}
            </MenuItem>
          );
        })}
      </div>
    );
  }

  function renderSubwalletsSection() {
    if (derivationsError) {
      return (
        <div className={styles.emptyList}>
          <span className={styles.emptyListTitle}>{lang(derivationsError)}</span>
        </div>
      );
    }

    return (
      <>
        <div className={styles.blockTitleRow}>
          <p className={buildClassName(styles.blockTitle, styles.blockTitle_small)}>{lang('Subwallets')}</p>
          {isLoadingDerivations ? (
            <span className={styles.scanningLabel}>
              <Spinner className={styles.scanningSpinner} />
              {lang('Scanning...')}
            </span>
          ) : hasWallets && (
            <span className={styles.scanningLabel}>
              {lang('$subwallets_found', groups.length, 'i')}
            </span>
          )}
        </div>
        {hasWallets
          ? renderSubwalletList()
          : !isLoadingDerivations && (
            <div className={styles.emptySubwallets}>
              {lang('No subwallets yet.')}
            </div>
          )}
      </>
    );
  }

  function renderUnifiedContent() {
    return (
      <div className={styles.slide}>
        <SettingsHeader
          title={lang('Subwallets')}
          isScrolled={isScrolled}
          onBackClick={handleBackToSettingsClick}
        />

        <div className={styles.contentWrapper}>
          <div
            className={buildClassName(styles.content, styles.contentWallets, 'custom-scroll')}
            onScroll={handleScroll}
          >
            <div className={styles.blockDescription}>
              {lang('Use subwallets to get additional addresses without creating new secret words.')}
            </div>

            {renderCurrentWalletBlock()}

            <div className={buildClassName(styles.blockDescription, styles.noTopMargin)}>
              {lang('If you have previously created subwallets, they will appear in the list below.')}
            </div>

            {renderSubwalletsSection()}
          </div>

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
      </div>
    );
  }

  function renderContent(isSlideActive: boolean, _isFrom: boolean, _currentKey: number) {
    switch (currentSlide) {
      case SLIDES.password:
        return (
          <div className={styles.slide}>
            <SettingsHeader
              title={lang('Confirm Password')}
              onBackClick={handleBackToSettingsClick}
            />
            <PasswordForm
              isActive={isSlideActive && !!isActive}
              error={passwordError}
              containerClassName={IS_CAPACITOR ? styles.passwordFormContent : styles.passwordFormWithHeaderOffset}
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
      name={resolveSlideTransitionName()}
      className={buildClassName(styles.transitionContainer, 'custom-scroll')}
      activeKey={currentSlide}
      withSwipeControl
    >
      {renderContent}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global)!;
  return {
    accountId: currentAccountId,
    tokens: selectCurrentAccountTokens(global),
    baseCurrency: global.settings.baseCurrency,
  };
})(SettingsWalletVariants));
