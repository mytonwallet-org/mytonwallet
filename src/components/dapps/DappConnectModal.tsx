import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { TonConnectProof } from '../../api/dappProtocols/adapters';
import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiDappPermissions } from '../../api/types';
import type { Account } from '../../global/types';
import { AppState, DappConnectState } from '../../global/types';

import {
  selectCurrentAccountId,
  selectEnclaveToken,
  selectHasPassword,
  selectIsEnclaveSessionValid,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import MfaConfirm from '../common/MfaConfirm';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import AddAccountPasswordModal from '../main/modals/accountSelector/AddAccountPasswordModal';
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
  multichainResolution?: 'switched-account' | 'needs-new-wallet';
  hasPassword: boolean;
  isAccountLoading?: boolean;
  isCreatingAccount?: boolean;
  accountError?: string;
  isAuthAppState?: boolean;
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
  currentAccountId,
  multichainResolution,
  hasPassword = false,
  isAccountLoading,
  isCreatingAccount,
  accountError,
  isAuthAppState,
}: StateProps) {
  const {
    submitDappConnectRequestConfirm,
    cancelDappConnectRequestConfirm,
    setDappConnectRequestState,
    resetHardwareWalletConnect,
    addAccount,
    clearAccountError,
    updateDappConnectMfaRequestStatus,
  } = getActions();

  const lang = useLang();
  const [selectedAccount, setSelectedAccount] = useState<string>(currentAccountId);

  const isOpen = hasConnectRequest && !(isCreatingAccount && isAuthAppState);

  const handleCloseAnimationEnd = useLastCallback(() => {
    if (!isCreatingAccount) {
      cancelDappConnectRequestConfirm();
    }
  });

  const { renderingKey, nextKey } = useModalTransitionKeys(state ?? 0, isOpen);

  const isLoading = dapp === undefined;

  const dappHost = useMemo(() => dapp && dapp.url ? new URL(dapp.url).host : undefined, [dapp]);

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
  const isNoCompatibleWallet = multichainResolution === 'needs-new-wallet';

  const handleOpenAccountSelector = useLastCallback(() => {
    setDappConnectRequestState({ state: DappConnectState.SelectAccount });
  });

  const handleSelectAccount = useLastCallback((accountId: string) => {
    setSelectedAccount(accountId);
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  const handleAccountSelectorBack = useLastCallback(() => {
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  const handleSubmit = useLastCallback(() => {
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
    } else if (selectIsEnclaveSessionValid(getGlobal())) {
      submitDappConnectRequestConfirm({
        accountId: selectedAccount,
        enclaveToken: selectEnclaveToken(getGlobal()),
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

  const handlePasswordSubmit = useLastCallback((enclaveToken: string) => {
    submitDappConnectRequestConfirm({
      accountId: selectedAccount,
      enclaveToken,
    });
  });

  const handleCreateMultichainWallet = useLastCallback(() => {
    if (!hasPassword || selectIsEnclaveSessionValid(getGlobal())) {
      addAccount({ method: 'createAccount', clearDappConnectOnVerified: true });
      return;
    }

    clearAccountError();
    setDappConnectRequestState({ state: DappConnectState.AddAccountPassword });
  });

  const handleAddAccountPasswordSubmit = useLastCallback((enclaveToken: string) => {
    addAccount({ method: 'createAccount', clearDappConnectOnVerified: true, enclaveToken });
  });

  const handleAddAccountPasswordCancel = useLastCallback(() => {
    clearAccountError();
    setDappConnectRequestState({ state: DappConnectState.Info });
  });

  function getIsAccountCompatible(byChain: Account['byChain']) {
    return !dapp?.chains?.length || dapp.chains.every(({ chain }) => Boolean(byChain[chain]));
  }

  const getIsAccountDisabled = useLastCallback((account: Account) => {
    if (isNoCompatibleWallet) return true;

    const isCompatible = getIsAccountCompatible(account.byChain);
    const accountHasMfa = Boolean(account.byChain.ton?.mfa);

    return !isCompatible || ((!!requiredProof || accountHasMfa) && isViewAccount(account.type));
  });

  const slideSubtitle = useMemo(() => (
    <span className={styles.accountSlideSubtitle}>
      {lang('Wallet to use on %host%', { host: dappHost })}
      {dapp?.urlTrustStatus !== 'verified' && (
        <DappHostWarning
          url={dapp?.url}
          urlTrustStatus={dapp?.urlTrustStatus}
          iconClassName={styles.dappLargePreviewHostWarning}
        />
      )}
    </span>
  ), [dapp?.url, dapp?.urlTrustStatus, dappHost, lang]);

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
          <p className={styles.dappLargePreviewDescription}>
            {lang(multichainResolution === 'needs-new-wallet'
              ? '$connect_dapp_no_compatible_wallets_found'
              : '$connect_dapp_description')}
          </p>
        </div>
        {(!isSelectedAccountCompatible || isNoCompatibleWallet) && (
          <div className={buildClassName(styles.multichainWarning, styles.warning)}>
            <div className={styles.warningTitle}>{lang('Unsupported Chain')}</div>
            {lang('Please upgrade to multichain to use this app.')}
          </div>
        )}

        <div className={styles.footer}>
          {multichainResolution === 'needs-new-wallet' ? (
            <Button
              isPrimary
              isLoading={isCreatingAccount}
              isDisabled={isViewMode}
              className={modalStyles.buttonFullWidth}
              onClick={handleCreateMultichainWallet}
            >
              {lang('Create Multichain Wallet')}
            </Button>
          ) : (
            <Button
              isPrimary
              isDestructive={dapp?.urlTrustStatus === 'dangerous'}
              isDisabled={isViewMode || !isSelectedAccountCompatible}
              className={modalStyles.buttonFullWidth}
              onClick={handleSubmit}
            >
              {lang(dapp?.urlTrustStatus === 'dangerous' ? 'Connect Anyway' : 'Connect Wallet')}
            </Button>
          )}
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
        <div className={styles.headerWithPill}>
          <ModalHeader onClose={cancelDappConnectRequestConfirm} />
          {shouldRenderAccountSelector && (
            <AccountSwitcherPill
              accountId={selectedAccount}
              title={accounts?.[selectedAccount]?.title}
              className={styles.accountPill}
              onClick={handleOpenAccountSelector}
            />
          )}
        </div>
        {isLoading ? renderWaitForConnection() : renderDappInfo()}
      </Transition>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: DappConnectState) {
    switch (currentKey) {
      case DappConnectState.Info:
        return renderDappInfoWithSkeleton();
      case DappConnectState.SelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            selectedAccountId={selectedAccount}
            subtitle={slideSubtitle}
            getIsAccountDisabled={getIsAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={handleAccountSelectorBack}
            onClose={cancelDappConnectRequestConfirm}
          />
        );
      case DappConnectState.Password:
        return (
          <DappPassword
            isActive={isActive}
            error={error}
            // Proving ownership to the dapp and signing the MFA request are separate signatures, so
            // a connection that does both reads the secret twice
            extraAuthUsages={requiredProof && isMfaEnabled ? 1 : 0}
            onAuthorize={handlePasswordSubmit}
            onCancel={handlePasswordCancel}
            onClose={cancelDappConnectRequestConfirm}
          />
        );
      case DappConnectState.AddAccountPassword:
        return (
          <AddAccountPasswordModal
            isActive={isActive}
            isLoading={isAccountLoading || isCreatingAccount}
            error={accountError}
            onClearError={clearAccountError}
            onAuthorize={handleAddAccountPasswordSubmit}
            onBack={handleAddAccountPasswordCancel}
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
      onCloseAnimationEnd={handleCloseAnimationEnd}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
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
    state, dapp, error, accountId, permissions, proof, mfaRequestHash, multichainResolution, isCreatingAccount,
  } = global.dappConnectRequest || {};
  const currentAccountId = accountId || selectCurrentAccountId(global)!;
  const hasConnectRequest = state !== undefined;

  if (!hasConnectRequest) {
    return { hasConnectRequest: false, currentAccountId };
  }

  const accounts = selectNetworkAccounts(global);

  const { accounts: accountsState } = global;

  const { isLoading: isAccountLoading, error: accountError } = accountsState ?? {};

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
    multichainResolution,
    hasPassword: selectHasPassword(global),
    isAccountLoading,
    isCreatingAccount,
    accountError,
    isAuthAppState: global.appState === AppState.Auth,
  };
})(DappConnectModal));

const ICON_FALLBACK = (
  <i
    className={buildClassName(styles.dappLargePreviewLogo, styles.dappLargePreviewLogo_icon, 'icon-laptop')}
    aria-hidden
  />
);
