import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { GlobalState, SavedAddress } from '../../global/types';
import { DomainLinkingState } from '../../global/types';

import { TONCOIN } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountState,
  selectCurrentToncoinBalance,
  selectTonDnsLinkedAddress,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { isValidAddressOrDomain } from '../../util/isValidAddress';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import useSyncEffectWithPrevDeps from '../../hooks/useSyncEffectWithPrevDeps';

import MfaConfirm from '../common/MfaConfirm';
import TransactionBanner from '../common/TransactionBanner';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import NftInfo from '../transfer/NftInfo';
import AddressInput from '../ui/AddressInput';
import Button from '../ui/Button';
import FeeLine from '../ui/FeeLine';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './RenewDomainModal.module.scss';

interface StateProps {
  isMediaViewerOpen?: boolean;
  currentDomainLinking: GlobalState['currentDomainLinking'];
  byAddress?: Record<string, ApiNft>;
  tonBalance: bigint;
  savedAddresses?: SavedAddress[];
  currentTonAddress?: string;
  currentLinkedWalletAddress?: string;
}

function LinkingDomainModal({
  currentDomainLinking: {
    address,
    isUnlinking,
    state,
    error,
    isLoading,
    realFee,
    walletAddress = '',
    walletAddressName = '',
    resolvedWalletAddress,
    mfaRequestHash,
  },
  isMediaViewerOpen,
  byAddress,
  tonBalance,
  savedAddresses,
  currentTonAddress,
  currentLinkedWalletAddress,
}: StateProps) {
  const {
    startDomainLinking,
    cancelDomainLinking,
    clearDomainLinkingError,
    submitDomainLinking,
    checkDomainLinkingDraft,
    checkLinkingAddress,
    setDomainLinkingWalletAddress,
    updateDomainLinkingMfaRequestStatus,
  } = getActions();

  const lang = useLang();

  const isOpen = state !== DomainLinkingState.None && !isMediaViewerOpen;
  const { renderingKey, nextKey } = useModalTransitionKeys(state ?? 0, isOpen);
  const domainNft = address ? byAddress?.[address] : undefined;
  const isInsufficientBalance = realFee ? tonBalance < realFee : undefined;
  const feeTerms = useMemo(() => (realFee ? { native: realFee } : undefined), [realFee]);
  const modalTitle = isUnlinking
    ? 'Unlink Wallet'
    : currentLinkedWalletAddress ? 'Change Linked Wallet' : 'Link to Wallet';
  const isAddressValid = isValidAddressOrDomain(walletAddress, 'ton');
  const [hasAddressFormatError, setHasAddressFormatError] = useState(false);

  const handleWalletAddressInput = useLastCallback((newToAddress?: string) => {
    // The controlled input drops keystrokes while its re-render waits for a heavy animation to end
    setDomainLinkingWalletAddress({ address: newToAddress }, { forceOnHeavyAnimation: true });
  });

  const canSubmit = (
    isUnlinking
      ? Boolean(currentLinkedWalletAddress)
      : isAddressValid && walletAddress !== currentLinkedWalletAddress
  ) && !isInsufficientBalance && !isLoading;

  useInterval(() => {
    if (isOpen && state === DomainLinkingState.ConfirmMfa && mfaRequestHash) {
      updateDomainLinkingMfaRequestStatus();
    }
  }, isOpen && state === DomainLinkingState.ConfirmMfa ? 1000 : undefined);

  useSyncEffectWithPrevDeps(([prevIsOpen]) => {
    if (!prevIsOpen && isOpen) {
      handleWalletAddressInput(walletAddress || currentLinkedWalletAddress || currentTonAddress);
    }
  }, [isOpen, currentLinkedWalletAddress, walletAddress, currentTonAddress]);

  useEffect(() => {
    if (isOpen) {
      checkDomainLinkingDraft({ nft: domainNft! });
    }
  }, [domainNft, isOpen]);

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    if (canSubmit) {
      submitDomainLinking({ enclaveToken });
    }
  });

  const handleHardwareSubmit = useLastCallback(() => {
    if (canSubmit) {
      submitDomainLinking();
    }
  });

  function renderInitialContent() {
    return (
      <>
        <ModalHeader title={lang(modalTitle)} onClose={cancelDomainLinking} />

        <div className={modalStyles.transitionContent}>
          <div className={styles.nftContainer}>
            <NftInfo nft={domainNft} withMediaViewer />

            <AddressInput
              withQrScan
              withCurrentAccount
              isReadonly={isUnlinking}
              value={walletAddress}
              // Domain linking is available only for TON blockchain
              addressBookChain="ton"
              chain="ton"
              savedAddresses={savedAddresses}
              validateAddress={checkLinkingAddress}
              label={currentLinkedWalletAddress ? lang('Linked Wallet') : lang('Wallet')}
              address={resolvedWalletAddress || walletAddress}
              addressName={walletAddressName}
              onInput={handleWalletAddressInput}
              onError={setHasAddressFormatError}
              onClose={cancelDomainLinking}
            />
          </div>

          <FeeLine terms={feeTerms} token={TONCOIN} precision="exact" isError={isInsufficientBalance} />
          <div className={buildClassName(modalStyles.buttons, styles.footer)}>
            <Button
              isPrimary
              isDisabled={!canSubmit}
              isLoading={!realFee || isLoading}
              className={styles.button}
              onClick={startDomainLinking}
            >
              {hasAddressFormatError
                ? lang('Invalid Address')
                : isInsufficientBalance
                  ? lang('Insufficient Balance')
                  : isUnlinking
                    ? lang('Unlink Wallet')
                    : lang('Link')}
            </Button>
          </div>
        </div>
      </>
    );
  }

  function renderPasswordForm(isActive: boolean) {
    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader
            title={isUnlinking ? lang('Confirm Unlinking') : lang('Confirm Linking')}
            onClose={cancelDomainLinking}
          />
        )}
        <PasswordForm
          isActive={isActive}
          error={error}
          isLoading={isLoading}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Cancel')}
          onAuthorize={handleAuthorize}
          onCancel={cancelDomainLinking}
          onUpdate={clearDomainLinkingError}
        >
          <TransactionBanner
            imageUrl={domainNft?.thumbnail}
            text={domainNft?.name ?? '1 domain'}
            className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
          />
        </PasswordForm>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: DomainLinkingState) {
    switch (currentKey) {
      case DomainLinkingState.Initial:
        return renderInitialContent();

      case DomainLinkingState.Password:
        return renderPasswordForm(isActive);

      case DomainLinkingState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleHardwareSubmit}
            onClose={cancelDomainLinking}
          />
        );

      case DomainLinkingState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelDomainLinking}
            onTryAgain={handleHardwareSubmit}
          />
        );

      case DomainLinkingState.ConfirmMfa:
        return (
          <>
            <ModalHeader onClose={cancelDomainLinking} />
            <MfaConfirm
              onClose={cancelDomainLinking}
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
      onClose={cancelDomainLinking}
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

export default memo(
  withGlobal((global): StateProps => {
    const {
      currentDomainLinking,
      mediaViewer: { mediaId },
    } = global;
    const currentAccount = selectCurrentAccount(global);
    const accountState = selectCurrentAccountState(global);
    const { byAddress } = accountState?.nfts || {};
    const domainNft = currentDomainLinking.address ? byAddress?.[currentDomainLinking.address] : undefined;
    const currentLinkedWalletAddress = domainNft ? selectTonDnsLinkedAddress(global, domainNft) : '';

    return {
      isMediaViewerOpen: Boolean(mediaId),
      currentDomainLinking,
      byAddress,
      tonBalance: selectCurrentToncoinBalance(global),
      savedAddresses: accountState?.savedAddresses,
      currentLinkedWalletAddress,
      currentTonAddress: currentAccount?.byChain.ton?.address,
    };
  })(LinkingDomainModal),
);
