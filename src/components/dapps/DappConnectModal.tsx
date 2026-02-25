import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { TonConnectProof } from '../../api/dappProtocols/adapters';
import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiBaseCurrency, ApiCurrencyRates, ApiDappPermissions, ApiStakingState } from '../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../global/types';
import { DappConnectState } from '../../global/types';

import {
  selectCurrentAccountId,
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../util/buildClassName';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import { type AccountBalance, useAccountsBalances } from '../main/modals/accountSelector/hooks/useAccountsBalances';

import AccountRowContent from '../common/AccountRowContent';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Button from '../ui/Button';
import Image from '../ui/Image';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Skeleton from '../ui/Skeleton';
import Transition from '../ui/Transition';
import DappHostWarning from './DappHostWarning';
import DappPassword from './DappPassword';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface StateProps {
  state?: DappConnectState;
  hasConnectRequest: boolean;
  dapp?: StoredDappConnection;
  error?: string;
  requiredPermissions?: ApiDappPermissions;
  requiredProof?: TonConnectProof;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  orderedAccounts: Array<[string, Account]>;
  settingsByAccountId?: Record<string, AccountSettings>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  byAccountId: GlobalState['byAccountId'];
  tokenInfo: GlobalState['tokenInfo'];
  stakingDefault: ApiStakingState;
  areTokensWithNoCostHidden?: boolean;
}

function DappConnectModal({
  state,
  hasConnectRequest,
  dapp,
  error,
  requiredPermissions,
  requiredProof,
  accounts,
  orderedAccounts,
  currentAccountId,
  settingsByAccountId,
  baseCurrency,
  currencyRates,
  byAccountId,
  tokenInfo,
  stakingDefault,
  areTokensWithNoCostHidden,
}: StateProps) {
  const {
    submitDappConnectRequestConfirm,
    cancelDappConnectRequestConfirm,
    setDappConnectRequestState,
    resetHardwareWalletConnect,
  } = getActions();

  const lang = useLang();
  const [selectedAccount, setSelectedAccount] = useState<string>(currentAccountId);
  const [isConfirmOpen, openConfirm, closeConfirm] = useFlag(false);

  const isOpen = hasConnectRequest;

  const { renderingKey, nextKey } = useModalTransitionKeys(state ?? 0, isOpen);

  const isLoading = dapp === undefined;

  const dappHost = useMemo(() => dapp && dapp.url ? new URL(dapp.url).host : undefined, [dapp]);

  const allAccountsTokens = useMemo(() => {
    if (!settingsByAccountId) return undefined;
    return selectMultipleAccountsTokensSlow(
      accounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }, [
    accounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ]);

  const allAccountsStakingStates = useMemo(() => {
    return selectMultipleAccountsStakingStatesSlow(
      accounts,
      byAccountId,
      stakingDefault,
    );
  }, [accounts, byAccountId, stakingDefault]);

  const { balancesByAccountId } = useAccountsBalances(
    orderedAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  ) as { balancesByAccountId: Record<string, AccountBalance | undefined> };

  useEffect(() => {
    if (!currentAccountId) return;

    setSelectedAccount(currentAccountId);
  }, [currentAccountId]);

  const shouldRenderAccountSelector = accounts && isKeyCountGreater(accounts, 1);

  const handleOpenAccountSelector = useLastCallback((_accountId: string) => {
    setDappConnectRequestState({ state: DappConnectState.SelectAccount });
  });

  const handleSelectAccount = useLastCallback((accountId: string) => {
    setSelectedAccount(accountId);
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  const handleAccountSelectorBack = useLastCallback(() => {
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  const handleSubmit = useLastCallback(async () => {
    closeConfirm();

    if (isViewAccount(accounts![selectedAccount].type) && requiredProof) return;

    const isHardware = accounts![selectedAccount].type === 'hardware';
    const { isPasswordRequired, isAddressRequired } = requiredPermissions || {};

    if (!requiredProof || (!isHardware && isAddressRequired && !isPasswordRequired)) {
      submitDappConnectRequestConfirm({
        accountId: selectedAccount,
      });

      // Closing the modal is delayed in order to `submitDappConnectRequestConfirm` cause the "confirmed" effect first
      requestAnimationFrame(() => {
        cancelDappConnectRequestConfirm();
      });
    } else if (isHardware) {
      resetHardwareWalletConnect({ chain: 'ton' });
      setDappConnectRequestState({ state: DappConnectState.ConnectHardware });
    } else if (getHasInMemoryPassword()) {
      submitDappConnectRequestConfirm({
        accountId: selectedAccount,
        password: await getInMemoryPassword(),
      });
    } else {
      // The confirmation window must be closed before the password screen is displayed
      requestAnimationFrame(() => {
        setDappConnectRequestState({ state: DappConnectState.Password });
      });
    }
  });

  const handlePasswordCancel = useLastCallback(() => {
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  const submitDappConnectRequestHardware = useLastCallback(() => {
    submitDappConnectRequestConfirm({
      accountId: selectedAccount,
    });
  });

  const handlePasswordSubmit = useLastCallback((password: string) => {
    submitDappConnectRequestConfirm({
      accountId: selectedAccount,
      password,
    });
  });

  function renderAccountSelector() {
    const account = accounts?.[selectedAccount];
    if (!account) return undefined;

    const { title, byChain, type } = account;
    const { cardBackgroundNft } = settingsByAccountId?.[selectedAccount] || {};
    const balanceData = balancesByAccountId?.[selectedAccount];

    return (
      <>
        <span className={styles.accountSelectorTitle}>{lang('Selected Wallet')}</span>
        <AccountRowContent
          accountId={selectedAccount}
          byChain={byChain}
          accountType={type}
          title={title}
          cardBackgroundNft={cardBackgroundNft}
          balanceData={balanceData}
          className={styles.accountSelectorButton}
          suffixIcon={<i className={buildClassName(styles.accountSelectorChevron, 'icon-chevron-right')} aria-hidden />}
          onClick={handleOpenAccountSelector}
        />
      </>
    );
  }

  function renderSelectAccountSlide() {
    return (
      <>
        <ModalHeader
          title={lang('Choose Wallet')}
          onBackButtonClick={handleAccountSelectorBack}
          onClose={cancelDappConnectRequestConfirm}
        />
        <div className={modalStyles.transitionContent}>
          <span className={buildClassName(styles.accountSelectorTitle, styles.accountSelectorTitle_2)}>
            {lang('Wallet to use on %host%', { host: dappHost })}
            {!dapp?.isUrlEnsured && (
              <DappHostWarning url={dapp?.url} iconClassName={styles.dappLargePreviewHostWarning} />
            )}
          </span>
          <div className={styles.accountList}>
            {orderedAccounts.map(([accountId, { title, byChain, type }]) => {
              const hasTonWallet = Boolean(byChain.ton);
              const isDisabled = !hasTonWallet || (!!requiredProof && isViewAccount(type));
              const isSelected = accountId === selectedAccount;
              const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};
              const balanceData = balancesByAccountId?.[accountId];

              return (
                <AccountRowContent
                  key={accountId}
                  accountId={accountId}
                  byChain={byChain}
                  accountType={type}
                  title={title}
                  cardBackgroundNft={cardBackgroundNft}
                  balanceData={balanceData}
                  isSelected={isSelected}
                  isDisabled={isDisabled}
                  className={styles.accountListItem}
                  onClick={handleSelectAccount}
                />
              );
            })}
          </div>
        </div>
      </>
    );
  }

  function renderDappInfo() {
    const isViewMode = Boolean(selectedAccount && requiredProof && isViewAccount(accounts?.[selectedAccount].type));

    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <div className={styles.dappLargePreviewBlock}>
          <Image
            url={dapp!.iconUrl}
            alt={dapp!.name}
            className={styles.dappLargePreviewLogo}
            imageClassName={styles.dappLargePreviewLogo}
            fallback={(
              <i
                className={buildClassName(
                  styles.dappLargePreviewLogo,
                  styles.dappLargePreviewLogo_icon,
                  'icon-laptop',
                )}
                aria-hidden
              />
            )}
          />

          <span className={styles.dappLargePreviewName}>{lang('$connect_dapp_title', { name: dapp?.name })}</span>
          <span className={styles.dappLargePreviewHost}>
            {dappHost}
            {!dapp?.isUrlEnsured && (
              <DappHostWarning url={dapp?.url} iconClassName={styles.dappLargePreviewHostWarning} />
            )}
          </span>
          <p className={styles.dappLargePreviewDescription}>{lang('$connect_dapp_description')}</p>
        </div>
        {shouldRenderAccountSelector && renderAccountSelector()}

        <div className={styles.footer}>
          <Button
            isPrimary
            isDisabled={isViewMode}
            className={modalStyles.buttonFullWidth}
            onClick={openConfirm}
          >
            {lang('Connect Wallet')}
          </Button>
        </div>
      </div>
    );
  }

  function renderWaitForConnection() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <div className={styles.dappLargePreviewBlock}>
          <Skeleton className={buildClassName(styles.dappLargePreviewLogo, styles.dappLargePreviewLogo_skeleton)} />
          <Skeleton className={buildClassName(styles.dappLargePreviewName, styles.dappLargePreviewName_skeleton)} />
          <Skeleton className={buildClassName(styles.dappLargePreviewHost, styles.dappLargePreviewHost_skeleton)} />
          <p className={styles.dappLargePreviewDescription}>{lang('$connect_dapp_description')}</p>
        </div>
      </div>
    );
  }

  function renderDappInfoWithSkeleton() {
    return (
      <Transition name="semiFade" activeKey={isLoading ? 0 : 1} slideClassName={styles.skeletonTransitionWrapper}>
        <ModalHeader onClose={cancelDappConnectRequestConfirm} />
        {isLoading ? renderWaitForConnection() : renderDappInfo()}
      </Transition>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: DappConnectState) {
    switch (currentKey) {
      case DappConnectState.Info:
        return renderDappInfoWithSkeleton();
      case DappConnectState.SelectAccount:
        return renderSelectAccountSlide();
      case DappConnectState.Password:
        return (
          <DappPassword
            isActive={isActive}
            error={error}
            onSubmit={handlePasswordSubmit}
            onCancel={handlePasswordCancel}
            onClose={cancelDappConnectRequestConfirm}
          />
        );
      case DappConnectState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={submitDappConnectRequestHardware}
            onClose={handlePasswordCancel}
          />
        );
      case DappConnectState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            isActive={isActive}
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onTryAgain={submitDappConnectRequestHardware}
            onClose={handlePasswordCancel}
          />
        );
    }
  }

  return (
    <>
      <Modal
        isOpen={isOpen}
        dialogClassName={styles.modalDialog}
        onClose={cancelDappConnectRequestConfirm}
        onCloseAnimationEnd={cancelDappConnectRequestConfirm}
      >
        <Transition
          name={resolveSlideTransitionName()}
          className={buildClassName(modalStyles.transition, 'custom-scroll')}
          slideClassName={modalStyles.transitionSlide}
          activeKey={renderingKey}
          nextKey={nextKey}
        >
          {renderContent}
        </Transition>
      </Modal>
      <Modal
        isOpen={isConfirmOpen}
        isCompact
        title={lang('Dapp Permissions')}
        onClose={closeConfirm}
      >
        <div className={styles.description}>
          {lang('$dapp_can_view_balance', {
            dappname: <strong>{dapp?.name}</strong>,
          })}
        </div>
        <div className={styles.buttons}>
          <Button onClick={closeConfirm} className={styles.button}>{lang('Cancel')}</Button>
          <Button isPrimary onClick={handleSubmit} className={styles.button}>{lang('Connect')}</Button>
        </div>
      </Modal>
    </>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accounts = selectNetworkAccounts(global);
  const orderedAccounts = selectOrderedAccounts(global);
  const hasConnectRequest = global.dappConnectRequest?.state !== undefined;

  const {
    state, dapp, error, accountId, permissions, proof,
  } = global.dappConnectRequest || {};

  const currentAccountId = accountId || selectCurrentAccountId(global)!;

  const {
    settings: {
      byAccountId: settingsByAccountId,
      baseCurrency,
      areTokensWithNoCostHidden,
    },
    currencyRates,
    byAccountId,
    tokenInfo,
    stakingDefault,
  } = global;

  return {
    state,
    hasConnectRequest,
    dapp,
    error,
    requiredPermissions: permissions,
    requiredProof: proof,
    currentAccountId,
    accounts,
    orderedAccounts,
    settingsByAccountId,
    baseCurrency,
    currencyRates,
    byAccountId,
    tokenInfo,
    stakingDefault,
    areTokensWithNoCostHidden,
  };
})(DappConnectModal));
