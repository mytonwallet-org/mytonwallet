import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../../../global/types';
import type { TabWithProperties } from '../../../ui/TabList';

import {
  selectCurrentAccountId,
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../../../util/captureEvents';
import { vibrate } from '../../../../util/haptics';
import { disableSwipeToClose, enableSwipeToClose } from '../../../../util/modalSwipeManager';
import resolveSlideTransitionName from '../../../../util/resolveSlideTransitionName';
import { IS_LEDGER_SUPPORTED, IS_TOUCH_ENV } from '../../../../util/windowEnvironment';

import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import { OPEN_CONTEXT_MENU_CLASS_NAME } from './hooks/useAccountContextMenu';
import { useAccountsBalances } from './hooks/useAccountsBalances';
import { useFilteredAccounts } from './hooks/useFilteredAccounts';
import { useSortableAccounts } from './hooks/useSortableAccounts';

import Modal from '../../../ui/Modal';
import TabList from '../../../ui/TabList';
import Transition from '../../../ui/Transition';
import { ADD_LEDGER_ACCOUNT, ADD_VIEW_ACCOUNT } from '../AddAccountModal';
import LogOutModal from '../LogOutModal';
import AccountRenameModal from './AccountRenameModal';
import AccountSelectorFooter from './AccountSelectorFooter';
import AccountSelectorHeader, { RenderingState } from './AccountSelectorHeader';
import AccountsGridView from './AccountsGridView';
import AccountsListView from './AccountsListView';

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
  isSortByValueEnabled?: boolean;
  areTokensWithNoCostHidden?: boolean;
  isSensitiveDataHidden?: true;
  isTestnet?: boolean;
}

export const enum AccountTab {
  My = 0,
  All = 1,
  Ledger = 2,
  View = 3,
}

export const TAB_TITLES = {
  [AccountTab.My]: 'My',
  [AccountTab.All]: 'All',
  [AccountTab.Ledger]: 'Ledger',
  [AccountTab.View]: '$view_accounts',
};

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
  activeTab = AccountTab.My,
  viewModeInitial,
  isSortByValueEnabled,
  areTokensWithNoCostHidden,
  isSensitiveDataHidden,
  isTestnet,
}: StateProps) {
  const {
    closeAccountSelector,
    switchAccount,
    openAddAccountModal,
    setAccountSelectorTab,
    setAccountSelectorViewMode,
    rebuildOrderedAccountIds,
  } = getActions();

  const lang = useLang();
  const contentRef = useRef<HTMLDivElement>();

  const allAccountsTokens = useMemo(() => {
    return selectMultipleAccountsTokensSlow(
      networkAccounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      isSortByValueEnabled,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }, [
    networkAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    isSortByValueEnabled,
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
  const initialRenderingKey = viewModeInitial === 'list' ? RenderingState.List : RenderingState.Cards;
  const [renderingKey, setRenderingKey] = useState<RenderingState>(initialRenderingKey);
  const [renameAccountId, setRenameAccountId] = useState<string | undefined>();
  const [isLogOutModalOpen, openLogOutModal, closeLogOutModal] = useFlag(false);
  const [logOutAccountId, setLogOutAccountId] = useState<string | undefined>();

  const tabs = useMemo((): TabWithProperties[] => {
    const result: TabWithProperties[] = [
      { id: AccountTab.My, title: lang(TAB_TITLES[AccountTab.My]) },
      { id: AccountTab.All, title: lang(TAB_TITLES[AccountTab.All]) },
    ];

    if (IS_LEDGER_SUPPORTED && !isTestnet) {
      result.push({ id: AccountTab.Ledger, title: lang(TAB_TITLES[AccountTab.Ledger]) });
    }

    result.push({ id: AccountTab.View, title: lang(TAB_TITLES[AccountTab.View]) });

    return result;
  }, [isTestnet, lang]);
  const currentTabIndex = useMemo(() => {
    const idx = tabs.findIndex((tab) => tab.id === activeTab);

    return idx >= 0 ? idx : 0;
  }, [activeTab, tabs]);
  const selectedTab = (tabs[currentTabIndex]?.id as AccountTab) ?? AccountTab.My;

  const {
    isScrolled,
    isAtEnd: noButtonsSeparator,
    update: handleScrollInitialize,
    handleScroll,
  } = useScrolledState();

  useEffect(() => {
    if (!isOpen) return undefined;

    disableSwipeToClose();

    return enableSwipeToClose;
  }, [isOpen]);

  const filteredAccounts = useFilteredAccounts(orderedAccounts, selectedTab);
  const { balancesByAccountId, totalBalance } = useAccountsBalances(
    filteredAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  );
  const { sortState, handleDrag, handleDragEnd } = useSortableAccounts(filteredAccounts);

  useEffectOnce(rebuildOrderedAccountIds);

  const handleCloseAccountSelectorForced = useLastCallback(() => {
    closeAccountSelector(undefined, { forceOnHeavyAnimation: true });
  });

  const handleSwitchAccount = useLastCallback((accountId: string) => {
    void vibrate();
    handleCloseAccountSelectorForced();

    if (accountId !== currentAccountId) {
      switchAccount({ accountId });
    }
  });

  const handleAddWalletClick = useLastCallback(() => {
    void vibrate();
    handleCloseAccountSelectorForced();

    const selectedTabId = tabs[currentTabIndex]?.id as AccountTab ?? AccountTab.My;
    let initialState: typeof ADD_LEDGER_ACCOUNT | typeof ADD_VIEW_ACCOUNT | undefined;
    if (selectedTabId === AccountTab.Ledger && IS_LEDGER_SUPPORTED && !isTestnet) {
      initialState = ADD_LEDGER_ACCOUNT;
    } else if (selectedTabId === AccountTab.View) {
      initialState = ADD_VIEW_ACCOUNT;
    }

    openAddAccountModal({ initialState });
  });

  const handleSwitchTab = useLastCallback((tabId: number) => {
    if (renderingKey === RenderingState.Reorder) return;

    setAccountSelectorTab({ tab: tabId });
  });

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isOpen) return;

    const node = contentRef.current;
    if (!node) return;

    function handleSwipe(e: Event, direction: SwipeDirection) {
      if (
        direction === SwipeDirection.Up
        || direction === SwipeDirection.Down
        || renderingKey === RenderingState.Reorder
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
  }, [tabs, handleSwitchTab, currentTabIndex, renderingKey, isOpen]);

  const handleModalClose = useLastCallback(() => {
    setRenderingKey(initialRenderingKey);
  });

  const handleViewModeChange = useLastCallback((state: RenderingState) => {
    setRenderingKey(state);

    if (state === RenderingState.List || state === RenderingState.Cards) {
      setAccountSelectorViewMode({ mode: state === RenderingState.List ? 'list' : 'cards' });
    }
  });

  const handleReorderClick = useLastCallback(() => {
    setRenderingKey(RenderingState.Reorder);
    setAccountSelectorTab({ tab: AccountTab.All });
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

  const handleReorderDoneClick = useLastCallback(() => {
    void vibrate();
    const previousMode = viewModeInitial === 'list' ? RenderingState.List : RenderingState.Cards;
    setRenderingKey(previousMode);
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: RenderingState) {
    switch (currentKey) {
      case RenderingState.Cards:
        return (
          <AccountsGridView
            isActive={isActive}
            isTestnet={isTestnet}
            filteredAccounts={filteredAccounts}
            activeTab={selectedTab}
            balancesByAccountId={balancesByAccountId}
            settingsByAccountId={settingsByAccountId}
            currentAccountId={currentAccountId}
            isSensitiveDataHidden={isSensitiveDataHidden}
            onSwitchAccount={handleSwitchAccount}
            onScrollInitialize={handleScrollInitialize}
            onScroll={handleScroll}
            onRename={handleRenameClick}
            onReorder={handleReorderClick}
            onLogOut={handleLogOutClick}
          />
        );

      case RenderingState.List:
        return (
          <AccountsListView
            isActive={isActive}
            isTestnet={isTestnet}
            filteredAccounts={filteredAccounts}
            activeTab={selectedTab}
            balancesByAccountId={balancesByAccountId}
            settingsByAccountId={settingsByAccountId}
            currentAccountId={currentAccountId}
            isSensitiveDataHidden={isSensitiveDataHidden}
            onScrollInitialize={handleScrollInitialize}
            onScroll={handleScroll}
            onSwitchAccount={handleSwitchAccount}
            onRename={handleRenameClick}
            onReorder={handleReorderClick}
            onLogOut={handleLogOutClick}
          />
        );

      case RenderingState.Reorder:
        return (
          <AccountsListView
            isActive={isActive}
            isTestnet={isTestnet}
            filteredAccounts={filteredAccounts}
            activeTab={selectedTab}
            balancesByAccountId={balancesByAccountId}
            settingsByAccountId={settingsByAccountId}
            currentAccountId={currentAccountId}
            isSensitiveDataHidden={isSensitiveDataHidden}
            onScrollInitialize={handleScrollInitialize}
            onScroll={handleScroll}
            onSwitchAccount={handleSwitchAccount}
            onRename={handleRenameClick}
            onReorder={handleReorderClick}
            onLogOut={handleLogOutClick}
            isReorder
            sortState={sortState}
            onDrag={handleDrag}
            onDragEnd={handleDragEnd}
          />
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
        nativeBottomSheetKey="account-selector"
        forceFullNative={renderingKey === RenderingState.Reorder}
        onCloseAnimationEnd={handleModalClose}
        onClose={handleCloseAccountSelectorForced}
      >
        <div className={buildClassName(styles.headerWrapper, isScrolled && styles.withBorder)}>
          <AccountSelectorHeader
            walletsCount={filteredAccounts.length}
            totalBalance={totalBalance}
            renderingState={renderingKey}
            isSensitiveDataHidden={isSensitiveDataHidden}
            onViewModeChange={handleViewModeChange}
            onReorderClick={handleReorderClick}
          />

          <div className={styles.tabsContainer}>
            <TabList
              tabs={tabs}
              activeTab={currentTabIndex}
              className={buildClassName(styles.tabs, renderingKey === RenderingState.Reorder && styles.inactive)}
              onSwitchTab={handleSwitchTab}
            />
          </div>
        </div>

        <Transition
          ref={contentRef}
          name={resolveSlideTransitionName()}
          className={buildClassName(
            modalStyles.transition,
            styles.rootTransition,
            IS_TOUCH_ENV && 'swipe-container',
          )}
          slideClassName={modalStyles.transitionSlide}
          activeKey={renderingKey}
        >
          {renderContent}
        </Transition>

        <AccountSelectorFooter
          tab={selectedTab}
          renderingState={renderingKey}
          withBorder={!noButtonsSeparator}
          onAddWallet={handleAddWalletClick}
          onReorderDone={handleReorderDoneClick}
        />
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
      isAccountSelectorOpen,
      accountSelectorActiveTab,
      currencyRates,
      settings: {
        byAccountId: settingsByAccountId,
        baseCurrency,
        isSensitiveDataHidden,
        isSortByValueEnabled,
        areTokensWithNoCostHidden,
        isTestnet,
      },
    } = global;

    const orderedAccounts = selectOrderedAccounts(global);
    const currentAccountId = selectCurrentAccountId(global)!;
    const networkAccounts = selectNetworkAccounts(global);

    return {
      isOpen: isAccountSelectorOpen,
      currentAccountId,
      orderedAccounts,
      networkAccounts,
      byAccountId: global.byAccountId,
      tokenInfo: global.tokenInfo,
      stakingDefault: global.stakingDefault,
      settingsByAccountId,
      baseCurrency,
      currencyRates,
      isSortByValueEnabled,
      areTokensWithNoCostHidden,
      isSensitiveDataHidden,
      activeTab: accountSelectorActiveTab,
      viewModeInitial: global.accountSelectorViewMode,
      isTestnet,
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(AccountSelectorModal));
