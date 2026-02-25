import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../../../global/types';
import { AccountSelectorState } from '../../../../global/types';
import { SettingsState } from '../../../../global/types';

import {
  selectCurrentAccountId,
  selectIsPasswordPresent,
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../../../util/captureEvents';
import { getChainsSupportingLedger } from '../../../../util/chain';
import { vibrate } from '../../../../util/haptics';
import { disableSwipeToClose, enableSwipeToClose } from '../../../../util/modalSwipeManager';
import { IS_LEDGER_SUPPORTED, IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { buildTabs, getCurrentTabIndex } from './helpers/tabsHelper';
import { AccountTab, DEFAULT_TAB, OPEN_CONTEXT_MENU_CLASS_NAME } from './constants';

import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import { useAccountsBalances } from './hooks/useAccountsBalances';
import { useFilteredAccounts } from './hooks/useFilteredAccounts';
import { useSortableAccounts } from './hooks/useSortableAccounts';

import AuthImportViewAccount from '../../../auth/AuthImportViewAccount';
import LedgerConnect from '../../../ledger/LedgerConnect';
import LedgerSelectWallets from '../../../ledger/LedgerSelectWallets';
import Modal from '../../../ui/Modal';
import TabList from '../../../ui/TabList';
import Transition from '../../../ui/Transition';
import LogOutModal from '../LogOutModal';
import AccountRenameModal from './AccountRenameModal';
import AccountSelectorFooter from './AccountSelectorFooter';
import AccountSelectorHeader from './AccountSelectorHeader';
import AccountsGridView from './AccountsGridView';
import AccountsListView from './AccountsListView';
import AddAccountPasswordModal from './AddAccountPasswordModal';
import AddAccountSelector from './AddAccountSelector';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './AccountSelectorModal.module.scss';

interface StateProps {
  isOpen?: boolean;
  currentAccountId: string;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  orderedAccounts: Array<[string, Account]>;
  networkAccounts?: Record<string, Account>;
  byAccountId: GlobalState['byAccountId'];
  tokenInfo: GlobalState['tokenInfo'];
  stakingDefault: ApiStakingState;
  settingsByAccountId: Record<string, AccountSettings>;
  activeTab?: number;
  viewModeInitial?: 'cards' | 'list';
  areTokensWithNoCostHidden?: boolean;
  isSensitiveDataHidden?: true;
  isTestnet?: boolean;
  isLoading?: boolean;
  error?: string;
  isPasswordPresent: boolean;
  withOtherWalletVersions?: boolean;
  forceAddingTonOnlyAccount?: boolean;
  initialAuthState?: AccountSelectorState;
  shouldHideAddAccountBackButton?: boolean;
}

function AccountSelectorModal({
  isOpen,
  currentAccountId,
  baseCurrency,
  currencyRates,
  orderedAccounts,
  networkAccounts,
  byAccountId,
  tokenInfo,
  stakingDefault,
  settingsByAccountId,
  activeTab = DEFAULT_TAB,
  viewModeInitial,
  areTokensWithNoCostHidden,
  isSensitiveDataHidden,
  isTestnet,
  isLoading,
  error,
  isPasswordPresent,
  withOtherWalletVersions,
  forceAddingTonOnlyAccount,
  initialAuthState,
  shouldHideAddAccountBackButton,
}: StateProps) {
  const {
    closeAccountSelector,
    switchAccount,
    setAccountSelectorTab,
    setAccountSelectorViewMode,
    rebuildOrderedAccountIds,
    addAccount,
    clearAccountError,
    openSettingsWithState,
    resetHardwareWalletConnect,
    clearAccountLoading,
  } = getActions();

  const lang = useLang();
  const contentRef = useRef<HTMLDivElement>();

  const allAccountsTokens = useMemo(() => {
    return selectMultipleAccountsTokensSlow(
      networkAccounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }, [
    networkAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ]);

  const allAccountsStakingStates = useMemo(() => {
    return selectMultipleAccountsStakingStatesSlow(
      networkAccounts,
      byAccountId,
      stakingDefault,
    );
  }, [networkAccounts, byAccountId, stakingDefault]);

  const initialRenderingKey = viewModeInitial === 'list'
    ? AccountSelectorState.List
    : AccountSelectorState.Cards;
  const [renderingKey, setRenderingKey] = useState<AccountSelectorState>(initialRenderingKey);
  const [renameAccountId, setRenameAccountId] = useState<string | undefined>();
  const [isLogOutModalOpen, openLogOutModal, closeLogOutModal] = useFlag(false);
  const [logOutAccountId, setLogOutAccountId] = useState<string | undefined>();
  const [isNewAccountImporting, setIsNewAccountImporting] = useState<boolean>(false);
  const [previousViewMode, setPreviousViewMode] = useState<AccountSelectorState>(initialRenderingKey);
  const [shouldReturnToStartScreen, setShouldReturnToStartScreen] = useState<boolean>(false);

  const tabs = useMemo(() => buildTabs(isTestnet ?? false, lang), [isTestnet, lang]);
  const currentTabIndex = useMemo(() => getCurrentTabIndex(tabs, activeTab), [activeTab, tabs]);
  const selectedTab = tabs[currentTabIndex]?.id ?? DEFAULT_TAB;
  const filteredAccounts = useFilteredAccounts(orderedAccounts, selectedTab);
  const { balancesByAccountId, totalBalance } = useAccountsBalances(
    filteredAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  );
  const { sortState, handleDrag, handleDragEnd } = useSortableAccounts(filteredAccounts);

  const {
    isScrolled,
    isAtEnd: noButtonsSeparator,
    update: handleScrollInitialize,
    handleScroll,
  } = useScrolledState();

  useEffectOnce(rebuildOrderedAccountIds);

  useEffect(() => {
    if (!isOpen) return undefined;

    disableSwipeToClose();

    return enableSwipeToClose;
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;

    if (forceAddingTonOnlyAccount) {
      handleNewAccountClick();
      return;
    }

    if (initialAuthState !== undefined) {
      const state = initialAuthState;
      if (state === AccountSelectorState.AddAccountConnectHardware && IS_LEDGER_SUPPORTED && !isTestnet) {
        handleImportHardwareWalletClick();
      } else if (state === AccountSelectorState.AddAccountViewMode) {
        setRenderingKey(AccountSelectorState.AddAccountViewMode);
      } else if (state === AccountSelectorState.AddAccountInitial) {
        setRenderingKey(AccountSelectorState.AddAccountInitial);
      } else {
        setRenderingKey(initialRenderingKey);
      }
    }
  }, [isOpen, forceAddingTonOnlyAccount, initialAuthState, initialRenderingKey, isTestnet]);

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isOpen) return;

    const node = contentRef.current;
    if (!node) return;

    function handleSwipe(e: Event, direction: SwipeDirection) {
      if (
        direction === SwipeDirection.Up
        || direction === SwipeDirection.Down
        || renderingKey === AccountSelectorState.Reorder
        || (e.target as HTMLElement | null)?.closest(`.${OPEN_CONTEXT_MENU_CLASS_NAME}`)

      ) {
        return false;
      }

      const nextIndex = direction === SwipeDirection.Left
        ? Math.min(tabs.length - 1, currentTabIndex + 1)
        : Math.max(0, currentTabIndex - 1);
      if (nextIndex === currentTabIndex) return false;

      const nextTab = tabs[nextIndex];
      handleSwitchTab(nextTab.id);
      return true;
    }

    return captureEvents(node, {
      includedClosestSelector: '.swipe-container',
      selectorToPreventScroll: '.custom-scroll',
      onSwipe: handleSwipe,
    });
  }, [currentTabIndex, isOpen, renderingKey, tabs]);

  const handleCloseAccountSelectorForced = useLastCallback(() => {
    closeAccountSelector(undefined, { forceOnHeavyAnimation: true });
  });

  const handleModalClose = useLastCallback(() => {
    setRenderingKey(initialRenderingKey);
    setIsNewAccountImporting(false);
    setShouldReturnToStartScreen(false);
    setPreviousViewMode(initialRenderingKey);
    clearAccountLoading();
  });

  const handleBackFromAddAccount = useLastCallback(() => {
    switch (renderingKey) {
      case AccountSelectorState.AddAccountPassword:
        setRenderingKey(AccountSelectorState.AddAccountInitial);
        clearAccountError();
        break;

      case AccountSelectorState.AddAccountViewMode:
      case AccountSelectorState.AddAccountConnectHardware:
        if (shouldReturnToStartScreen) {
          setRenderingKey(previousViewMode);
          setShouldReturnToStartScreen(false);
        } else {
          setRenderingKey(AccountSelectorState.AddAccountInitial);
        }
        break;

      case AccountSelectorState.AddAccountSelectHardware:
        setRenderingKey(AccountSelectorState.AddAccountConnectHardware);
        break;

      default:
        setRenderingKey(previousViewMode);
    }
  });

  const handleSwitchAccount = useLastCallback((accountId: string) => {
    void vibrate();
    handleCloseAccountSelectorForced();

    if (accountId !== currentAccountId) {
      switchAccount({ accountId });
    }
  });

  const handleAddAccountAction = useLastCallback((method: 'createAccount' | 'importMnemonic') => {
    if (!isPasswordPresent) {
      addAccount({ method, password: '' });
      return;
    }

    if (getHasInMemoryPassword()) {
      void getInMemoryPassword()
        .then((password) => addAccount({
          method,
          password: password!,
        }));
      return;
    }

    setIsNewAccountImporting(method === 'importMnemonic');
    setRenderingKey(AccountSelectorState.AddAccountPassword);
  });

  const handleNewAccountClick = useLastCallback(() => {
    handleAddAccountAction('createAccount');
  });

  const handleImportAccountClick = useLastCallback(() => {
    handleAddAccountAction('importMnemonic');
  });

  const handleImportHardwareWalletClick = useLastCallback(() => {
    resetHardwareWalletConnect({
      chain: getChainsSupportingLedger()[0],
      shouldLoadWallets: true,
    });
    setRenderingKey(AccountSelectorState.AddAccountConnectHardware);
  });

  const handleViewModeWalletClick = useLastCallback(() => {
    setShouldReturnToStartScreen(false);
    setRenderingKey(AccountSelectorState.AddAccountViewMode);
  });

  const handleSubmitPassword = useLastCallback((password: string) => {
    addAccount({ method: isNewAccountImporting ? 'importMnemonic' : 'createAccount', password });
  });

  const handleHardwareWalletConnected = useLastCallback(() => {
    setRenderingKey(AccountSelectorState.AddAccountSelectHardware);
  });

  const handleViewModeChange = useLastCallback((state: AccountSelectorState) => {
    setRenderingKey(state);

    if (state === AccountSelectorState.List || state === AccountSelectorState.Cards) {
      setAccountSelectorViewMode({ mode: state === AccountSelectorState.List ? 'list' : 'cards' });
    }
  });

  const handleSwitchTab = useLastCallback((tabId: number) => {
    if (renderingKey === AccountSelectorState.Reorder) return;

    setAccountSelectorTab({ tab: tabId });
  });

  const handleAddWalletClick = useLastCallback(() => {
    void vibrate();
    setPreviousViewMode(renderingKey);

    const selectedTabId = tabs[currentTabIndex]?.id ?? AccountTab.My;
    if (selectedTabId === AccountTab.View) {
      setShouldReturnToStartScreen(true);
      setRenderingKey(AccountSelectorState.AddAccountViewMode);
    } else if (selectedTabId === AccountTab.Ledger) {
      setShouldReturnToStartScreen(true);
      handleImportHardwareWalletClick();
    } else {
      setShouldReturnToStartScreen(false);
      setRenderingKey(AccountSelectorState.AddAccountInitial);
    }
  });

  const handleReorderClick = useLastCallback(() => {
    setRenderingKey(AccountSelectorState.Reorder);
    setAccountSelectorTab({ tab: AccountTab.All });
  });

  const handleReorderDoneClick = useLastCallback(() => {
    void vibrate();
    const previousMode = viewModeInitial === 'list'
      ? AccountSelectorState.List
      : AccountSelectorState.Cards;
    setRenderingKey(previousMode);
  });

  const handleRenameClick = useLastCallback((accountId: string) => {
    void vibrate();
    setRenameAccountId(accountId);
  });

  const handleRenameClose = useLastCallback(() => {
    setRenameAccountId(undefined);
  });

  const handleLogOutClick = useLastCallback((accountId: string) => {
    void vibrate();
    setLogOutAccountId(accountId);
    openLogOutModal();
  });

  const handleLogOutModalClose = useLastCallback(() => {
    closeLogOutModal();
    setLogOutAccountId(undefined);

    if (filteredAccounts.length === 0 || currentAccountId === logOutAccountId) {
      handleCloseAccountSelectorForced();
    }
  });

  const handleOpenSettingWalletVersion = useLastCallback(() => {
    handleCloseAccountSelectorForced();
    openSettingsWithState({ state: SettingsState.WalletVersion });
  });

  function renderHeader(renderingState: AccountSelectorState, selectedTab: AccountTab) {
    const isInactiveTabs = renderingKey === AccountSelectorState.Reorder;

    return (
      <div className={buildClassName(styles.headerWrapper, isScrolled && styles.withBorder)}>
        <AccountSelectorHeader
          walletsCount={filteredAccounts.length}
          totalBalance={totalBalance}
          renderingState={renderingState}
          isSensitiveDataHidden={isSensitiveDataHidden}
          onViewModeChange={handleViewModeChange}
          onReorderClick={handleReorderClick}
        />

        <div className={styles.tabsContainer}>
          <TabList
            tabs={tabs}
            activeTab={currentTabIndex}
            className={buildClassName(styles.tabs, isInactiveTabs && styles.inactive)}
            onSwitchTab={handleSwitchTab}
          />
        </div>
      </div>
    );
  }

  function renderFooter(renderingState: AccountSelectorState, selectedTab: AccountTab) {
    return (
      <AccountSelectorFooter
        tab={selectedTab}
        renderingState={renderingState}
        withBorder={!noButtonsSeparator}
        onAddWallet={handleAddWalletClick}
        onReorderDone={handleReorderDoneClick}
      />
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: AccountSelectorState) {
    const commonAccountsViewProps = {
      isActive,
      isTestnet,
      filteredAccounts,
      activeTab: selectedTab,
      balancesByAccountId,
      settingsByAccountId,
      currentAccountId,
      isSensitiveDataHidden,
      onScrollInitialize: handleScrollInitialize,
      onScroll: handleScroll,
      onSwitchAccount: handleSwitchAccount,
      onRename: handleRenameClick,
      onReorder: handleReorderClick,
      onLogOut: handleLogOutClick,
    };

    switch (currentKey) {
      case AccountSelectorState.Cards:
        return (
          <>
            {renderHeader(AccountSelectorState.Cards, selectedTab)}
            <AccountsGridView {...commonAccountsViewProps} />
            {renderFooter(AccountSelectorState.Cards, selectedTab)}
          </>
        );

      case AccountSelectorState.List:
        return (
          <>
            {renderHeader(AccountSelectorState.List, selectedTab)}
            <AccountsListView {...commonAccountsViewProps} />
            {renderFooter(AccountSelectorState.List, selectedTab)}
          </>
        );

      case AccountSelectorState.Reorder:
        return (
          <>
            {renderHeader(AccountSelectorState.Reorder, selectedTab)}
            <AccountsListView
              {...commonAccountsViewProps}
              isReorder
              sortState={sortState}
              onDrag={handleDrag}
              onDragEnd={handleDragEnd}
            />
            {renderFooter(AccountSelectorState.Reorder, selectedTab)}
          </>
        );

      case AccountSelectorState.AddAccountInitial:
        return (
          <AddAccountSelector
            isNewAccountImporting={isNewAccountImporting}
            isLoading={isLoading}
            isTestnet={isTestnet}
            withOtherWalletVersions={withOtherWalletVersions}
            shouldHideBackButton={shouldHideAddAccountBackButton}
            onBack={handleBackFromAddAccount}
            onNewAccountClick={handleNewAccountClick}
            onImportAccountClick={handleImportAccountClick}
            onImportHardwareWalletClick={handleImportHardwareWalletClick}
            onViewModeWalletClick={handleViewModeWalletClick}
            onOpenSettingWalletVersion={handleOpenSettingWalletVersion}
            onClose={handleCloseAccountSelectorForced}
          />
        );

      case AccountSelectorState.AddAccountPassword:
        return (
          <AddAccountPasswordModal
            isActive={isActive}
            isLoading={isLoading}
            error={error}
            onClearError={clearAccountError}
            onSubmit={handleSubmitPassword}
            onBack={handleBackFromAddAccount}
            onClose={handleCloseAccountSelectorForced}
          />
        );

      case AccountSelectorState.AddAccountConnectHardware:
        return (
          <div className={buildClassName(modalStyles.transitionContentWrapper, styles.compensateSafeArea)}>
            <LedgerConnect
              isActive={isActive}
              onConnected={handleHardwareWalletConnected}
              onBackButtonClick={handleBackFromAddAccount}
              onClose={handleCloseAccountSelectorForced}
            />
          </div>
        );

      case AccountSelectorState.AddAccountSelectHardware:
        return (
          <div className={buildClassName(modalStyles.transitionContentWrapper, styles.compensateSafeArea)}>
            <LedgerSelectWallets
              withCloseButton
              onBackButtonClick={handleBackFromAddAccount}
              onClose={handleCloseAccountSelectorForced}
            />
          </div>
        );

      case AccountSelectorState.AddAccountViewMode:
        return (
          <div className={buildClassName(
            modalStyles.transitionContentWrapper,
            styles.compensateSafeArea,
            styles.compensateSafeAreaViewAccount,
          )}
          >
            <AuthImportViewAccount
              isActive={isActive}
              isLoading={isLoading}
              isInModal
              onCancel={handleBackFromAddAccount}
              onClose={handleCloseAccountSelectorForced}
            />
          </div>
        );
    }
  }

  return (
    <>
      <Modal
        hasCloseButton
        isOpen={isOpen}
        dialogClassName={styles.modalDialog}
        contentClassName={styles.modalContent}
        onCloseAnimationEnd={handleModalClose}
        onClose={handleCloseAccountSelectorForced}
      >
        <Transition
          ref={contentRef}
          name="semiFade"
          className={buildClassName(
            modalStyles.transition,
            styles.rootTransition,
            IS_TOUCH_ENV && 'swipe-container',
          )}
          slideClassName={buildClassName(modalStyles.transitionSlide, styles.rootTransitionSlide)}
          activeKey={renderingKey}
        >
          {renderContent}
        </Transition>
      </Modal>

      <AccountRenameModal
        isOpen={!!renameAccountId}
        accountId={renameAccountId ?? currentAccountId}
        onClose={handleRenameClose}
      />

      <LogOutModal isOpen={isLogOutModalOpen} onClose={handleLogOutModalClose} targetAccountId={logOutAccountId} />
    </>
  );
}

export default memo(withGlobal(
  (global): StateProps => {
    const {
      accounts,
      accountSelectorActiveTab: activeTab,
      accountSelectorViewMode: viewModeInitial,
      auth: {
        forceAddingTonOnlyAccount,
        initialAddAccountState: initialAuthState,
        shouldHideAddAccountBackButton,
      },
      byAccountId,
      currencyRates,
      isAccountSelectorOpen: isOpen,
      settings: {
        byAccountId: settingsByAccountId,
        baseCurrency,
        isSensitiveDataHidden,
        areTokensWithNoCostHidden,
        isTestnet,
      },
      stakingDefault,
      tokenInfo,
      walletVersions,
    } = global;

    const orderedAccounts = selectOrderedAccounts(global);
    const currentAccountId = selectCurrentAccountId(global)!;
    const networkAccounts = selectNetworkAccounts(global);
    const isPasswordPresent = selectIsPasswordPresent(global);
    const withOtherWalletVersions = Boolean(walletVersions?.byId?.[currentAccountId]?.length);
    const { isLoading, error } = accounts ?? {};

    return {
      isOpen,
      currentAccountId,
      orderedAccounts,
      networkAccounts,
      byAccountId,
      tokenInfo,
      stakingDefault,
      settingsByAccountId,
      baseCurrency,
      currencyRates,
      areTokensWithNoCostHidden,
      isSensitiveDataHidden,
      activeTab,
      viewModeInitial,
      isTestnet,
      isLoading,
      error,
      isPasswordPresent,
      withOtherWalletVersions,
      forceAddingTonOnlyAccount,
      initialAuthState,
      shouldHideAddAccountBackButton,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(AccountSelectorModal));
