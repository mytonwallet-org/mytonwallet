import React, {
  memo, useEffect, useMemo,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState, SavedAddress, UserToken } from '../../global/types';
import { TransferState } from '../../global/types';

import { BURN_ADDRESS, NFT_BATCH_SIZE } from '../../config';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { getIsViewAccountDisabled } from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { shortenAddress } from '../../util/shortenAddress';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import usePrevious from '../../hooks/usePrevious';

import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import TransactionBanner from '../common/TransactionBanner';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import Modal from '../ui/Modal';
import Transition from '../ui/Transition';
import TransferComplete from './TransferComplete';
import TransferConfirm from './TransferConfirm';
import TransferConfirmMfa from './TransferConfirmMfa';
import TransferInitial from './TransferInitial';
import TransferMultiNftProcess from './TransferMultiNftProcess';
import TransferPassword from './TransferPassword';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Transfer.module.scss';

interface StateProps {
  currentTransfer: GlobalState['currentTransfer'];
  currentAccountId?: string;
  tokens?: UserToken[];
  savedAddresses?: SavedAddress[];
  isMediaViewerOpen?: boolean;
}

function TransferModal({
  currentTransfer: {
    state,
    amount,
    toAddress,
    comment,
    error,
    isLoading,
    txId,
    tokenSlug,
    nfts,
    sentNftsCount,
    diesel,
    isNftBurn,
  },
  currentAccountId,
  tokens,
  savedAddresses,
  isMediaViewerOpen,
}: StateProps) {
  const {
    submitTransferConfirm,
    submitTransfer,
    setTransferScreen,
    cancelTransfer,
    showActivityInfo,
    switchTransferAccount,
  } = getActions();

  const lang = useLang();
  const isOpen = state !== TransferState.None;

  const selectedToken = useMemo(() => tokens?.find((token) => token.slug === tokenSlug), [tokenSlug, tokens]);
  const decimals = selectedToken?.decimals;
  const renderedTransactionAmount = usePrevious(amount, true);
  const symbol = selectedToken?.symbol || '';
  const isNftTransfer = Boolean(nfts?.length);
  // A transfer of more NFTs than fit in one transaction is sent as one API call per batch, and every
  // call signs on its own, so the batches past the first need a secret read each
  const extraNftBatchCount = nfts?.length ? Math.ceil(nfts.length / NFT_BATCH_SIZE) - 1 : 0;
  const isBurning = toAddress === BURN_ADDRESS || isNftBurn;
  // After confirming the transaction, `toAddress` is set to empty string, so we need to use the previous value
  const renderedToAddress = usePrevious(toAddress || undefined, true);

  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  useEffect(() => (
    state === TransferState.Confirm
      ? captureKeyboardListeners({ onEnter: () => submitTransferConfirm() })
      : undefined
  ), [state, submitTransferConfirm]);

  const handleTransferSubmit = useLastCallback((enclaveToken: string) => {
    submitTransfer({ enclaveToken });
  });

  const handleBackClick = useLastCallback(() => {
    if (state === TransferState.Confirm) {
      setTransferScreen({ state: TransferState.Initial });
    }
    if (state === TransferState.Password) {
      setTransferScreen({ state: TransferState.Confirm });
    }
  });

  const handleTransactionInfoClick = useLastCallback(() => {
    cancelTransfer({ shouldReset: true });
    showActivityInfo({ id: txId! });
  });

  const handleClose = useLastCallback(() => {
    cancelTransfer({ shouldReset: true });
  });

  const handleLedgerConnect = useLastCallback(() => {
    submitTransfer();
  });

  const handleSelectAccount = useLastCallback((accountId: string) => {
    switchTransferAccount({ accountId });
  });

  const handleSelectAccountBack = useLastCallback(() => {
    setTransferScreen({ state: TransferState.Initial });
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: TransferState) {
    switch (currentKey) {
      case TransferState.Initial:
        return (
          <TransferInitial key={currentAccountId} />
        );
      case TransferState.SelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsViewAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={handleSelectAccountBack}
            onClose={handleClose}
          />
        );
      case TransferState.Confirm:
        return (
          <TransferConfirm
            isActive={isActive}
            token={selectedToken}
            savedAddresses={savedAddresses}
            onBack={handleBackClick}
            onClose={handleClose}
          />
        );
      case TransferState.Password:
        return (
          <TransferPassword
            isActive={isActive}
            isLoading={isLoading}
            isBurning={isBurning}
            error={error}
            extraAuthUsages={extraNftBatchCount}
            onAuthorize={handleTransferSubmit}
            onCancel={handleClose}
            isGaslessWithStars={diesel?.status === 'stars-fee'}
          >
            <TransactionBanner
              tokenIn={selectedToken}
              imageUrl={nfts?.[0]?.thumbnail}
              withChainIcon
              text={isNftTransfer
                ? (nfts.length > 1 ? lang('%amount% NFTs', nfts.length, 'i') : nfts[0]?.name || 'NFT')
                : formatCurrency(toDecimal(amount!, decimals), symbol)}
              className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
              secondText={shortenAddress(toAddress!)}
              isTextHidden={isBurning}
            />
          </TransferPassword>
        );
      case TransferState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleLedgerConnect}
            onClose={handleClose}
          />
        );
      case TransferState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm transfer on your Ledger')}
            error={error}
            onClose={handleClose}
            onTryAgain={handleLedgerConnect}
          />
        );
      case TransferState.Complete:
        return (nfts?.length || 0) <= NFT_BATCH_SIZE ? (
          <TransferComplete
            isActive={isActive}
            nfts={nfts}
            isNftBurn={isNftBurn}
            amount={renderedTransactionAmount}
            symbol={symbol}
            txId={txId}
            tokenSlug={tokenSlug}
            toAddress={renderedToAddress}
            comment={comment}
            onInfoClick={handleTransactionInfoClick}
            onClose={handleClose}
            decimals={decimals}
          />
        ) : (
          <TransferMultiNftProcess
            nfts={nfts!}
            sentNftsCount={sentNftsCount}
            toAddress={renderedToAddress}
            onClose={handleClose}
          />
        );
      case TransferState.ConfirmMfa:
        return (
          <TransferConfirmMfa
            isActive={isActive}
            onClose={handleClose}
          >
            <TransactionBanner
              tokenIn={selectedToken}
              imageUrl={nfts?.[0]?.thumbnail}
              withChainIcon
              text={isNftTransfer
                ? (nfts.length > 1 ? lang('%amount% NFTs', nfts.length, 'i') : nfts[0]?.name || 'NFT')
                : formatCurrency(toDecimal(amount!, decimals), symbol)}
              className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
              secondText={shortenAddress(toAddress!)}
            />
          </TransferConfirmMfa>
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen && !isMediaViewerOpen}
      noBackdropClose
      dialogClassName={styles.modalDialog}
      onClose={handleClose}
      onCloseAnimationEnd={updateNextKey}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountState = selectCurrentAccountState(global);

  return {
    currentTransfer: global.currentTransfer,
    currentAccountId: selectCurrentAccountId(global),
    tokens: selectCurrentAccountTokens(global),
    savedAddresses: accountState?.savedAddresses,
    isMediaViewerOpen: Boolean(global.mediaViewer.mediaId),
  };
})(TransferModal));
