import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingState, ApiWalletWithVersionInfo,
} from '../../../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../../../global/types';
import { AccountSelectorState } from '../../../../global/types';
import { SettingsState } from '../../../../global/types';

import {
  selectCurrentAccountId,
  selectEnclaveToken,
  selectHasPassword,
  selectIsEnclaveSessionValid,
  selectIsMnemonicAccount,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
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
import { useMultipleAccountsBalances } from '../../../../hooks/useMultipleAccountsBalances';
import useScrolledState from '../../../../hooks/useScrolledState';
import useSortableList from '../../../../hooks/useSortableList';
import useSyncEffect from '../../../../hooks/useSyncEffect';
import { useFilteredAccounts } from './hooks/useFilteredAccounts';

import AuthImportViewAccount from '../../../auth/AuthImportViewAccount';
import LedgerConnect from '../../../ledger/LedgerConnect';
import LedgerSelectWallets from '../../../ledger/LedgerSelectWallets';
import Modal from '../../../ui/Modal';
import TabList from '../../../ui/TabList';
import Transition from '../../../ui/Transition';
import LogOutModal from '../LogOutModal';
import AccountSelectorFooter from './AccountSelectorFooter';
import AccountSelectorHeader from './AccountSelectorHeader';
import AccountsGridView from './AccountsGridView';
import AccountsListView, { ACCOUNT_HEIGHT_PX } from './AccountsListView';
import AddAccountPasswordModal from './AddAccountPasswordModal';
import AddAccountSelector from './AddAccountSelector';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './AccountSelectorModal.module.scss';

interface AccountSelectorOpenProps {
  isOpen: true;
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
  hasPassword: boolean;
  accountWalletVersions?: ApiWalletWithVersionInfo[];
  canAddSubwallet: boolean;
  forceAddingTonOnlyAccount?: boolean;
  initialAuthState?: AccountSelectorState;
  shouldHideAddAccountBackButton?: boolean;
}

type StateProps = AccountSelectorOpenProps
  | ({ isOpen: false } & Partial<Omit<AccountSelectorOpenProps, 'isOpen'>>);

function AccountSelectorModal({
  isOpen,
  currentAccountId = '',
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
  hasPassword,
  accountWalletVersions,
  canAddSubwallet = false,
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
    updateOrderedAccountIds,
    addAccount,
    createSubWallet,
    clearAccountError,
    openSettingsWithState,
    resetHardwareWalletConnect,
    clearAccountLoading,
    openWalletRenameModal,
  } = getActions();

  const lang = useLang();
  const contentRef = useRef<HTMLDivElement>();

  const initialRenderingKey = viewModeInitial === 'list'
    ? AccountSelectorState.List
    : AccountSelectorState.Cards;
  const [renderingKey, setRenderingKey] = useState<AccountSelectorState>(initialRenderingKey);
  const skipAnimationToKeyRef = useRef<AccountSelectorState | undefined>();
  const [isLogOutModalOpen, openLogOutModal, closeLogOutModal] = useFlag(false);
  const [logOutAccountId, setLogOutAccountId] = useState<string | undefined>();
  const [isNewAccountImporting, setIsNewAccountImporting] = useState<boolean>(false);
  const [isAddingSubwallet, setIsAddingSubwallet] = useState<boolean>(false);
  const [previousViewMode, setPreviousViewMode] = useState<AccountSelectorState>(initialRenderingKey);
  const [shouldReturnToStartScreen, setShouldReturnToStartScreen] = useState<boolean>(false);

  const hasOtherWalletVersions = useMemo(() => (
    (accountWalletVersions?.filter((v) => v.lastTxId || v.version === 'W5').length ?? 0) > 1
  ), [accountWalletVersions]);

  const tabs = useMemo(() => buildTabs(isTestnet ?? false, lang), [isTestnet, lang]);
  const currentTabIndex = useMemo(() => getCurrentTabIndex(tabs, activeTab), [activeTab, tabs]);
  const selectedTab = tabs[currentTabIndex]?.id ?? DEFAULT_TAB;
  const filteredAccounts = useFilteredAccounts(orderedAccounts, selectedTab);
  const { balancesByAccountId, totalBalance, addressLineChainsByAccountId } = useMultipleAccountsBalances({
    filteredAccounts,
    sourceAccounts: networkAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });
  const orderedAccountIds = useMemo(
    () => filteredAccounts.map(([accountId]) => accountId),
    [filteredAccounts],
  );
  const handleAccountsOrderChange = useLastCallback((newOrder: string[]) => {
    updateOrderedAccountIds({ orderedAccountIds: newOrder });
  });
  const { sortState, handleDrag, handleDragEnd } = useSortableList(
    orderedAccountIds,
    ACCOUNT_HEIGHT_PX,
    handleAccountsOrderChange,
  );

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

  useSyncEffect(() => {
    if (!isOpen || forceAddingTonOnlyAccount || initialAuthState === undefined) {
      skipAnimationToKeyRef.current = undefined;
      return;
    }

    const state = initialAuthState;
    let targetKey: AccountSelectorState;
    if (state === AccountSelectorState.AddAccountConnectHardware && IS_LEDGER_SUPPORTED && !isTestnet) {
      targetKey = AccountSelectorState.AddAccountConnectHardware;
    } else if (state === AccountSelectorState.AddAccountViewMode
      || state === AccountSelectorState.AddAccountInitial) {
      targetKey = state;
    } else {
      targetKey = initialRenderingKey;
    }

    skipAnimationToKeyRef.current = targetKey;
    setRenderingKey(targetKey);
  }, [isOpen, forceAddingTonOnlyAccount, initialAuthState, initialRenderingKey, isTestnet]);

  useEffect(() => {
    if (!isOpen) return;

    if (forceAddingTonOnlyAccount) {
      handleNewAccountClick();
      return;
    }

    if (initialAuthState === AccountSelectorState.AddAccountConnectHardware && IS_LEDGER_SUPPORTED && !isTestnet) {
      handleImportHardwareWalletClick();
    }
  }, [isOpen, forceAddingTonOnlyAccount, initialAuthState, isTestnet]);

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
    setIsAddingSubwallet(false);
    setShouldReturnToStartScreen(false);
    setPreviousViewMode(initialRenderingKey);
    clearAccountLoading();
  });

  const handleBackFromAddAccount = useLastCallback(() => {
    switch (renderingKey) {
      case AccountSelectorState.AddAccountPassword:
        setRenderingKey(AccountSelectorState.AddAccountInitial);
        setIsAddingSubwallet(false);
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
    vibrate();
    handleCloseAccountSelectorForced();

    if (accountId !== currentAccountId) {
      switchAccount({ accountId });
    }
  });

  const handleNewAccountClick = useLastCallback(() => {
    if (!hasPassword || selectIsEnclaveSessionValid(getGlobal())) {
      addAccount({ method: 'createAccount' });

      return;
    }
    setIsNewAccountImporting(false);
    setRenderingKey(AccountSelectorState.AddAccountPassword);
  });

  const handleImportAccountClick = useLastCallback(() => {
    if (!hasPassword) {
      addAccount({ method: 'importMnemonic' });

      return;
    }

    setIsNewAccountImporting(true);

    if (selectIsEnclaveSessionValid(getGlobal())) {
      addAccount({ method: 'importMnemonic' });

      return;
    }
    setRenderingKey(AccountSelectorState.AddAccountPassword);
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

  const handleSubmit = useLastCallback((enclaveToken: string) => {
    if (isAddingSubwallet) {
      createSubWallet({ enclaveToken });
      handleCloseAccountSelectorForced();
      return;
    }

    addAccount({ method: isNewAccountImporting ? 'importMnemonic' : 'createAccount', enclaveToken });
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
    vibrate();
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
    vibrate();
    const previousMode = viewModeInitial === 'list'
      ? AccountSelectorState.List
      : AccountSelectorState.Cards;
    setRenderingKey(previousMode);
  });

  const handleRenameClick = useLastCallback((accountId: string) => {
    vibrate();
    openWalletRenameModal({ accountId });
  });

  const handleLogOutClick = useLastCallback((accountId: string) => {
    vibrate();
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
    openSettingsWithState({ state: SettingsState.WalletVersions });
  });

  const handleNewSubwalletClick = useLastCallback(() => {
    if (selectIsEnclaveSessionValid(getGlobal())) {
      const enclaveToken = selectEnclaveToken(getGlobal());
      if (enclaveToken) {
        createSubWallet({ enclaveToken });
        handleCloseAccountSelectorForced();
        return;
      }
    }

    if (!hasPassword) {
      addAccount({ method: 'createAccount' });
      return;
    }

    setIsAddingSubwallet(true);
    setRenderingKey(AccountSelectorState.AddAccountPassword);
  });

  function renderHeader(renderingState: AccountSelectorState) {
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
      addressLineChainsByAccountId,
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
            {renderHeader(AccountSelectorState.Cards)}
            <AccountsGridView {...commonAccountsViewProps} />
            {renderFooter(AccountSelectorState.Cards, selectedTab)}
          </>
        );

      case AccountSelectorState.List:
        return (
          <>
            {renderHeader(AccountSelectorState.List)}
            <AccountsListView {...commonAccountsViewProps} />
            {renderFooter(AccountSelectorState.List, selectedTab)}
          </>
        );

      case AccountSelectorState.Reorder:
        return (
          <>
            {renderHeader(AccountSelectorState.Reorder)}
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
            hasOtherWalletVersions={hasOtherWalletVersions}
            canAddSubwallet={canAddSubwallet}
            shouldHideBackButton={shouldHideAddAccountBackButton}
            onBack={handleBackFromAddAccount}
            onNewAccountClick={handleNewAccountClick}
            onNewSubwalletClick={handleNewSubwalletClick}
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
            onAuthorize={handleSubmit}
            onBack={handleBackFromAddAccount}
            onClose={handleCloseAccountSelectorForced}
          />
        );

      case AccountSelectorState.AddAccountConnectHardware:
        return (
          <div className={modalStyles.transitionContentWrapper}>
            <LedgerConnect
              isActive={isActive}
              onConnected={handleHardwareWalletConnected}
              onBackClick={handleBackFromAddAccount}
              onClose={handleCloseAccountSelectorForced}
            />
          </div>
        );

      case AccountSelectorState.AddAccountSelectHardware:
        return (
          <div className={modalStyles.transitionContentWrapper}>
            <LedgerSelectWallets
              withCloseButton
              onBackClick={handleBackFromAddAccount}
              onClose={handleCloseAccountSelectorForced}
            />
          </div>
        );

      case AccountSelectorState.AddAccountViewMode:
        return (
          <div className={modalStyles.transitionContentWrapper}>
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

  // When opened with `initialAuthState`, Transition sees a key change (old → target) and animates.
  // We pass `name="none"` to make this switch instant, then clear the flag once `renderingKey`
  // catches up to the target so that subsequent navigations animate normally.
  const shouldSkipTransition = skipAnimationToKeyRef.current !== undefined;
  if (skipAnimationToKeyRef.current === renderingKey) {
    skipAnimationToKeyRef.current = undefined;
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
          name={shouldSkipTransition ? 'none' : 'semiFade'}
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

      <LogOutModal isOpen={isLogOutModalOpen} onClose={handleLogOutModalClose} targetAccountId={logOutAccountId} />
    </>
  );
}

export default memo(withGlobal(
  (global): StateProps => {
    const isOpen = global.isAccountSelectorOpen;

    if (!isOpen) {
      return { isOpen: false };
    }

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
    const hasPassword = selectHasPassword(global);
    const canAddSubwallet = selectIsMnemonicAccount(global);
    const accountWalletVersions = walletVersions?.byId?.[currentAccountId];
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
      hasPassword,
      accountWalletVersions,
      canAddSubwallet,
      forceAddingTonOnlyAccount,
      initialAuthState,
      shouldHideAddAccountBackButton,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(AccountSelectorModal));
