import React, {
  memo, useEffect, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiTonConnectProof } from '../../api/tonConnect/types';
import type { ApiDapp, ApiDappPermissions } from '../../api/types';
import type { Account, AccountSettings, AccountType } from '../../global/types';
import { DappConnectState } from '../../global/types';

import { selectNetworkAccounts } from '../../global/selectors';
import { getMainAccountAddress } from '../../util/account';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../util/buildClassName';
import { isKeyCountGreater } from '../../util/isEmptyObject';
import isViewAccount from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import AccountButton from '../common/AccountButton';
import AccountButtonWrapper from '../common/AccountButtonWrapper';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Button from '../ui/Button';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Skeleton from '../ui/Skeleton';
import Transition from '../ui/Transition';
import DappInfo from './DappInfo';
import DappPassword from './DappPassword';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface StateProps {
  state?: DappConnectState;
  hasConnectRequest: boolean;
  dapp?: ApiDapp;
  error?: string;
  requiredPermissions?: ApiDappPermissions;
  requiredProof?: ApiTonConnectProof;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  settingsByAccountId?: Record<string, AccountSettings>;
}

function DappConnectModal({
  state,
  hasConnectRequest,
  dapp,
  error,
  requiredPermissions,
  requiredProof,
  accounts,
  currentAccountId,
  settingsByAccountId,
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

  const iterableAccounts = useMemo(() => Object.entries(accounts || {}), [accounts]);
  const isLoading = dapp === undefined;

  useEffect(() => {
    if (!currentAccountId) return;

    setSelectedAccount(currentAccountId);
  }, [currentAccountId]);

  const shouldRenderAccounts = accounts && isKeyCountGreater(accounts, 1);

  const handleSubmit = useLastCallback(async () => {
    closeConfirm();
    const isViewMode = isViewAccount(accounts![selectedAccount].type);
    const isHardware = accounts![selectedAccount].type === 'hardware';
    const { isPasswordRequired, isAddressRequired } = requiredPermissions || {};

    if (isViewMode) return;

    if (!requiredProof || (!isHardware && isAddressRequired && !isPasswordRequired)) {
      submitDappConnectRequestConfirm({
        accountId: selectedAccount,
      });

      // Closing the modal is delayed in order to `submitDappConnectRequestConfirm` cause the "confirmed" effect first
      requestAnimationFrame(() => {
        cancelDappConnectRequestConfirm();
      });
    } else if (isHardware) {
      resetHardwareWalletConnect();
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

  function renderAccount(
    accountId: string,
    addressByChain: Account['addressByChain'],
    accountType: AccountType,
    title?: string,
  ) {
    const hasTonWallet = Boolean(addressByChain.ton);
    const onClick = !hasTonWallet || isViewAccount(accountType) ? undefined : () => setSelectedAccount(accountId);
    const address = getMainAccountAddress(addressByChain) ?? '';
    const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};

    return (
      <AccountButton
        key={accountId}
        accountId={accountId}
        address={address}
        title={title}
        ariaLabel={lang('Switch Account')}
        accountType={accountType}
        isActive={accountId === selectedAccount}
        isLoading={isLoading}

        onClick={onClick}
        cardBackgroundNft={cardBackgroundNft}
      />
    );
  }

  function renderAccounts() {
    return (
      <AccountButtonWrapper
        accountLength={iterableAccounts.length}
        labelText={lang('Select wallet to use on this dapp')}
      >
        {iterableAccounts.map(
          ([accountId, { title, addressByChain, type }]) => {
            return renderAccount(accountId, addressByChain, type, title);
          },
        )}
      </AccountButtonWrapper>
    );
  }

  function renderDappInfo() {
    const isViewMode = Boolean(selectedAccount && isViewAccount(accounts?.[selectedAccount].type));

    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappInfo
          dapp={dapp}
          className={buildClassName(styles.dapp_first, styles.dapp_push)}
        />
        {shouldRenderAccounts && renderAccounts()}

        <div className={styles.footer}>
          <Button
            isPrimary
            isDisabled={isViewMode}
            className={modalStyles.buttonFullWidth}
            onClick={openConfirm}
          >
            {lang('Connect')}
          </Button>
        </div>
      </div>
    );
  }

  function renderWaitForConnection() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <div className={buildClassName(styles.dappInfoSkeleton, styles.dapp_first)}>
          <Skeleton className={styles.dappInfoIconSkeleton} />
          <div className={styles.dappInfoTextSkeleton}>
            <Skeleton className={styles.nameSkeleton} />
            <Skeleton className={styles.descSkeleton} />
          </div>
        </div>
        <div className={styles.accountWrapperSkeleton}>
          {shouldRenderAccounts && renderAccounts()}
        </div>
      </div>
    );
  }

  function renderDappInfoWithSkeleton() {
    return (
      <Transition name="semiFade" activeKey={isLoading ? 0 : 1} slideClassName={styles.skeletonTransitionWrapper}>
        <ModalHeader title={lang('Connect Dapp')} onClose={cancelDappConnectRequestConfirm} />
        {isLoading ? renderWaitForConnection() : renderDappInfo()}
      </Transition>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: DappConnectState) {
    switch (currentKey) {
      case DappConnectState.Info:
        return renderDappInfoWithSkeleton();
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
            text={lang('Please confirm operation on your Ledger')}
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
        nativeBottomSheetKey="dapp-connect"
        // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
        forceFullNative={renderingKey !== DappConnectState.Info}
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
  const hasConnectRequest = global.dappConnectRequest?.state !== undefined;

  const {
    state, dapp, error, accountId, permissions, proof,
  } = global.dappConnectRequest || {};

  const currentAccountId = accountId || global.currentAccountId!;

  return {
    state,
    hasConnectRequest,
    dapp,
    error,
    requiredPermissions: permissions,
    requiredProof: proof,
    currentAccountId,
    accounts,
    settingsByAccountId: global.settings.byAccountId,
  };
})(DappConnectModal));
