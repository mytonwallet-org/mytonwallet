import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { TonConnectProof } from '../../api/dappProtocols/adapters';
import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiBaseCurrency, ApiCurrencyRates, ApiDappPermissions, ApiStakingState } from '../../api/types';
import type { Account, AccountSettings, GlobalState } from '../../global/types';
import { DappConnectState } from '../../global/types';

import {
  selectCurrentAccountId,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../util/buildClassName';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import { useMultipleAccountsBalances } from '../../hooks/useMultipleAccountsBalances';

import AccountRowContent from '../common/AccountRowContent';
import MfaConfirm from '../common/MfaConfirm';
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

interface DappConnectOpenProps {
  hasConnectRequest: true;
  state?: DappConnectState;
  dapp?: StoredDappConnection;
  error?: string;
  requiredPermissions?: ApiDappPermissions;
  requiredProof?: TonConnectProof;
  mfaRequestHash?: string;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  orderedAccounts: Array<[string, Account]>;
  settingsByAccountId: Record<string, AccountSettings>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  byAccountId: GlobalState['byAccountId'];
  tokenInfo: GlobalState['tokenInfo'];
  stakingDefault: ApiStakingState;
  areTokensWithNoCostHidden?: boolean;
}

type StateProps = DappConnectOpenProps
  | ({ hasConnectRequest: false; currentAccountId: string } & Partial<Omit<DappConnectOpenProps, 'hasConnectRequest'>>);

function DappConnectModal({
  state,
  hasConnectRequest,
  dapp,
  error,
  requiredPermissions,
  requiredProof,
  mfaRequestHash,
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
    updateDappConnectMfaRequestStatus,
  } = getActions();

  const lang = useLang();
  const [selectedAccount, setSelectedAccount] = useState<string>(currentAccountId);

  const isOpen = hasConnectRequest;

  const { renderingKey, nextKey } = useModalTransitionKeys(state ?? 0, isOpen);

  const isLoading = dapp === undefined;

  const dappHost = useMemo(() => dapp && dapp.url ? new URL(dapp.url).host : undefined, [dapp]);

  const { balancesByAccountId } = useMultipleAccountsBalances({
    filteredAccounts: orderedAccounts,
    sourceAccounts: accounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });

  useEffect(() => {
    if (!currentAccountId) return;

    setSelectedAccount(currentAccountId);
  }, [currentAccountId]);

  const isMfaEnabled = Boolean(accounts?.[selectedAccount]?.byChain?.ton?.mfa);

  useInterval(() => {
    if (isOpen && state === DappConnectState.ConfirmMfa && mfaRequestHash) {
      updateDappConnectMfaRequestStatus();
    }
  }, isOpen && state === DappConnectState.ConfirmMfa ? 1000 : undefined);

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
    if (isViewAccount(accounts![selectedAccount].type) && (requiredProof || isMfaEnabled)) return;

    const isHardware = accounts![selectedAccount].type === 'hardware';
    const { isPasswordRequired, isAddressRequired } = requiredPermissions || {};
    const doesNeedSigning = Boolean(requiredProof || isMfaEnabled);

    if (!doesNeedSigning || (!isMfaEnabled && !isHardware && isAddressRequired && !isPasswordRequired)) {
      submitDappConnectRequestConfirm({
        accountId: selectedAccount,
      });

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

  function getIsAccountCompatible(byChain: Account['byChain']) {
    return !dapp?.chains?.length || dapp.chains.every(({ chain }) => Boolean(byChain[chain]));
  }

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
            {dapp?.urlTrustStatus !== 'verified' && (
              <DappHostWarning
                url={dapp?.url}
                urlTrustStatus={dapp?.urlTrustStatus}
                iconClassName={styles.dappLargePreviewHostWarning}
              />
            )}
          </span>
          <div className={styles.accountList}>
            {(orderedAccounts ?? []).map(([accountId, { title, byChain, type }]) => {
              const isCompatible = getIsAccountCompatible(byChain);
              const accountHasMfa = Boolean(byChain.ton?.mfa);
              const isDisabled = !isCompatible || ((!!requiredProof || accountHasMfa) && isViewAccount(type));
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
    const isViewMode = Boolean(
      selectedAccount
      && isViewAccount(accounts?.[selectedAccount]?.type)
      && (requiredProof || isMfaEnabled),
    );
    const isSelectedAccountCompatible = getIsAccountCompatible(accounts?.[selectedAccount]?.byChain ?? {});

    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <div className={styles.dappLargePreviewBlock}>
          <Image
            forceLoaded
            url={dapp!.iconUrl}
            alt={dapp!.name}
            className={styles.dappLargePreviewLogo}
            imageClassName={styles.dappLargePreviewLogo}
            fallback={ICON_FALLBACK}
          />

          <span className={styles.dappLargePreviewName}>{lang('$connect_dapp_title', { name: dapp?.name })}</span>
          <span className={styles.dappLargePreviewHost}>
            {dappHost}
            {dapp?.urlTrustStatus !== 'verified' && (
              <DappHostWarning
                url={dapp?.url}
                urlTrustStatus={dapp?.urlTrustStatus}
                iconClassName={styles.dappLargePreviewHostWarning}
              />
            )}
          </span>
          <p className={styles.dappLargePreviewDescription}>{lang('$connect_dapp_description')}</p>
        </div>
        {shouldRenderAccountSelector && renderAccountSelector()}
        {!isSelectedAccountCompatible && (
          <div className={buildClassName(styles.multichainWarning, styles.warning)}>
            <div className={styles.warningTitle}>{lang('Unsupported Chain')}</div>
            {lang('Please upgrade to multichain to use this app.')}
          </div>
        )}

        <div className={styles.footer}>
          <Button
            isPrimary
            isDestructive={dapp?.urlTrustStatus === 'dangerous'}
            isDisabled={isViewMode || !isSelectedAccountCompatible}
            className={modalStyles.buttonFullWidth}
            onClick={handleSubmit}
          >
            {lang(dapp?.urlTrustStatus === 'dangerous' ? 'Connect Anyway' : 'Connect Wallet')}
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
      case DappConnectState.ConfirmMfa:
        return (
          <>
            <ModalHeader onClose={cancelDappConnectRequestConfirm} />
            <MfaConfirm
              onClose={cancelDappConnectRequestConfirm}
              mfaRequestHash={mfaRequestHash}
            />
          </>
        );
    }
  }

  return (
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
  );
}

export default memo(withGlobal((global): StateProps => {
  const {
    state, dapp, error, accountId, permissions, proof, mfaRequestHash,
  } = global.dappConnectRequest || {};
  const currentAccountId = accountId || selectCurrentAccountId(global)!;
  const hasConnectRequest = state !== undefined;

  if (!hasConnectRequest) {
    return { hasConnectRequest: false, currentAccountId };
  }

  const accounts = selectNetworkAccounts(global);
  const orderedAccounts = selectOrderedAccounts(global);

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
    mfaRequestHash,
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

const ICON_FALLBACK = (
  <i
    className={buildClassName(styles.dappLargePreviewLogo, styles.dappLargePreviewLogo_icon, 'icon-laptop')}
    aria-hidden
  />
);
