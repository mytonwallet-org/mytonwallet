import React, { memo, useEffect, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { GlobalState } from '../../global/types';
import { DomainRenewalState } from '../../global/types';

import { TONCOIN } from '../../config';
import { selectCurrentAccountState, selectCurrentToncoinBalance } from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { formatFullDay, formatTime, MINUTE, YEAR } from '../../util/dateFormat';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useForceUpdate from '../../hooks/useForceUpdate';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import TransactionBanner from '../common/TransactionBanner';
import LedgerConfirmOperation from '../ledger/LedgerConfirmOperation';
import LedgerConnect from '../ledger/LedgerConnect';
import NftChips from '../transfer/NftChips';
import NftInfo from '../transfer/NftInfo';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
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
  currentDomainRenewal: GlobalState['currentDomainRenewal'];
  byAddress?: Record<string, ApiNft>;
  tonBalance: bigint;
}

const THUMBNAILS_COUNT = 3;

function RenewDomainModal({
  currentDomainRenewal: {
    addresses,
    state,
    error,
    isLoading,
    realFee,
    txId,
  },
  isMediaViewerOpen,
  byAddress,
  tonBalance,
}: StateProps) {
  const {
    startDomainsRenewal,
    cancelDomainsRenewal,
    clearDomainsRenewalError,
    submitDomainsRenewal,
    checkDomainsRenewalDraft,
    showActivityInfo,
  } = getActions();

  const lang = useLang();
  const forceUpdate = useForceUpdate();

  const isOpen = state !== DomainRenewalState.None && !isMediaViewerOpen;
  const { renderingKey, nextKey } = useModalTransitionKeys(state ?? 0, isOpen);
  const domainNfts = useMemo(() => {
    return (addresses || []).map((address) => byAddress?.[address]).filter<ApiNft>(Boolean);
  }, [addresses, byAddress]);
  const isInsufficientBalance = realFee ? tonBalance < realFee : undefined;
  const feeTerms = useMemo(() => (realFee ? { native: realFee } : undefined), [realFee]);
  const newExpireTimestamp = Date.now() + YEAR;
  const domainNftThumbnails = useMemo(() => {
    return domainNfts.map((nft) => nft?.thumbnail).filter(Boolean).slice(0, THUMBNAILS_COUNT);
  }, [domainNfts]);

  useInterval(forceUpdate, isOpen ? MINUTE : undefined, true);
  useEffect(() => {
    if (isOpen) {
      checkDomainsRenewalDraft({ nfts: domainNfts });
    }
  }, [domainNfts, isOpen]);

  const handlePasswordSubmit = useLastCallback((password: string) => {
    submitDomainsRenewal({ password });
  });

  const handleHardwareSubmit = useLastCallback(() => {
    submitDomainsRenewal();
  });

  const handleInfoClick = useLastCallback(() => {
    cancelDomainsRenewal();
    showActivityInfo({ id: txId! });
  });

  function renderHeader() {
    return (
      <div className={buildClassName(modalStyles.header, modalStyles.header_wideContent)}>
        <div className={buildClassName(modalStyles.title, styles.modalTitle)}>
          <div className={styles.headerTitle}>
            {lang(addresses && addresses.length > 1 ? 'Renew Domains' : 'Renew Domain')}
          </div>
          {!!newExpireTimestamp && (
            <div className={styles.headerDate}>
              {lang('Until %date%', {
                date: [formatFullDay(lang.code!, newExpireTimestamp), formatTime(newExpireTimestamp)].join(', '),
              })}
            </div>
          )}
        </div>
        <Button isRound className={modalStyles.closeButton} ariaLabel={lang('Close')} onClick={cancelDomainsRenewal}>
          <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
        </Button>
      </div>
    );
  }

  function renderInitialContent() {
    return (
      <div className={modalStyles.transitionContent}>
        <div className={styles.nftContainer}>
          {domainNfts.length === 1 && <NftInfo nft={domainNfts[0]} withMediaViewer />}
          {domainNfts.length > 1 && <NftChips nfts={domainNfts} className={styles.multiNftChips} />}
        </div>

        <FeeLine terms={feeTerms} token={TONCOIN} precision="exact" />
        <div className={buildClassName(modalStyles.buttons, styles.footer)}>
          <Button
            isPrimary
            isDestructive={isInsufficientBalance}
            isDisabled={isInsufficientBalance}
            isLoading={!realFee || isLoading}
            className={styles.button}
            onClick={startDomainsRenewal}
          >
            {isInsufficientBalance
              ? lang('Insufficient Balance')
              : domainNfts.length > 1
                ? lang('Renew All')
                : lang('Renew')}
          </Button>
        </div>
      </div>
    );
  }

  function renderPasswordForm(isActive: boolean) {
    return (
      <>
        {!getDoesUsePinPad() && <ModalHeader title={lang('Confirm Renewing')} onClose={cancelDomainsRenewal} />}
        <PasswordForm
          isActive={isActive}
          error={error}
          isLoading={isLoading}
          submitLabel={lang('Confirm')}
          cancelLabel={lang('Cancel')}
          onSubmit={handlePasswordSubmit}
          onCancel={cancelDomainsRenewal}
          onUpdate={clearDomainsRenewalError}
        >
          <TransactionBanner
            imageUrl={domainNftThumbnails}
            text={
              domainNfts.length === 1 && Boolean(domainNfts[0]?.name)
                ? domainNfts[0]?.name
                : lang('$domains_amount %1$d', domainNfts.length, 'i')
            }
            className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
          />
        </PasswordForm>
      </>
    );
  }

  function renderComplete(isActive: boolean) {
    return (
      <>
        <ModalHeader
          title={domainNfts.length > 1 ? lang('Domains have been renewed!') : lang('Domain has been renewed!')}
          onClose={cancelDomainsRenewal}
        />

        <div className={modalStyles.transitionContent}>
          <AnimatedIconWithPreview
            play={isActive}
            noLoop={false}
            nonInteractive
            className={styles.sticker}
            tgsUrl={ANIMATED_STICKERS_PATHS.thumbUp}
            previewUrl={ANIMATED_STICKERS_PATHS.thumbUpPreview}
          />
          <div className={styles.nftContainer}>
            {domainNfts.length === 1 && <NftInfo nft={domainNfts[0]} withMediaViewer />}
            {domainNfts.length > 1 && <NftChips nfts={domainNfts} />}

            {domainNfts.length === 1 && !!txId && (
              <div className={buildClassName(styles.buttons, styles.buttonsAfterNft)}>
                <Button onClick={handleInfoClick}>{lang('Details')}</Button>
              </div>
            )}
          </div>

          <div className={modalStyles.buttons}>
            <Button onClick={cancelDomainsRenewal} isPrimary>
              {lang('Close')}
            </Button>
          </div>
        </div>
      </>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: DomainRenewalState) {
    switch (currentKey) {
      case DomainRenewalState.Initial:
        return (
          <>
            {renderHeader()}
            {renderInitialContent()}
          </>
        );

      case DomainRenewalState.Password:
        return renderPasswordForm(isActive);

      case DomainRenewalState.ConnectHardware:
        return (
          <LedgerConnect
            isActive={isActive}
            onConnected={handleHardwareSubmit}
            onClose={cancelDomainsRenewal}
          />
        );

      case DomainRenewalState.ConfirmHardware:
        return (
          <LedgerConfirmOperation
            text={lang('Please confirm action on your Ledger')}
            error={error}
            onClose={cancelDomainsRenewal}
            onTryAgain={handleHardwareSubmit}
          />
        );

      case DomainRenewalState.Complete:
        return renderComplete(isActive);
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      onClose={cancelDomainsRenewal}
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
      currentDomainRenewal,
      mediaViewer: { mediaId },
    } = global;
    const { byAddress } = selectCurrentAccountState(global)?.nfts || {};

    return {
      isMediaViewerOpen: Boolean(mediaId),
      currentDomainRenewal,
      byAddress,
      tonBalance: selectCurrentToncoinBalance(global),
    };
  })(RenewDomainModal),
);
