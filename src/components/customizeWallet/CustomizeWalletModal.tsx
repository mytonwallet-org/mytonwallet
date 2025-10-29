import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { Account, Theme, UserToken } from '../../global/types';

import { MTW_CARDS_COLLECTION, MTW_CARDS_WEBSITE } from '../../config';
import {
  selectAccount, selectAccountSettings, selectAccountState, selectCurrentAccountTokens,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { openUrl } from '../../util/openUrl';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import AccentColorSelector from '../common/AccentColorSelector';
import Button from '../ui/Button';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Spinner from '../ui/Spinner';
import Transition from '../ui/Transition';
import CardGrid from './CardGrid';
import EmptyState from './EmptyState';
import WalletCardPreview from './WalletCardPreview';

import modalStyles from '../ui/Modal.module.scss';
import styles from './CustomizeWalletModal.module.scss';

interface OwnProps {
  isOpen?: boolean;
}

interface StateProps {
  accountId?: string;
  account?: Account;
  nfts?: Record<string, ApiNft>;
  orderedNftAddresses?: string[];
  currentCardNft?: ApiNft;
  accentColorIndex?: number;
  tokens?: UserToken[];
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  theme: Theme;
  isMintingCardsAvailable?: boolean;
  isViewMode?: boolean;
  isNftBuyingDisabled: boolean;
  returnTo?: 'settings' | 'accountSelector';
}

function CustomizeWalletModal({
  isOpen,
  accountId,
  account,
  nfts,
  orderedNftAddresses,
  currentCardNft,
  accentColorIndex,
  tokens,
  baseCurrency,
  currencyRates,
  theme,
  isMintingCardsAvailable,
  isViewMode,
  isNftBuyingDisabled,
  returnTo,
}: OwnProps & StateProps) {
  const {
    closeCustomizeWalletModal,
    setCardBackgroundNft,
    clearCardBackgroundNft,
    openMintCardModal,
  } = getActions();

  const lang = useLang();
  const [selectedCardAddress, setSelectedCardAddress] = useState<string | undefined>(currentCardNft?.address);

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const availableCardNfts = useMemo(() => {
    if (!orderedNftAddresses || !nfts) return undefined;

    return orderedNftAddresses
      .map((address) => nfts[address])
      .filter((nft) => nft && nft.collectionAddress === MTW_CARDS_COLLECTION && !nft.isHidden);
  }, [orderedNftAddresses, nfts]);

  const isLoading = availableCardNfts === undefined;
  const hasCards = availableCardNfts && availableCardNfts.length > 0;

  const selectedCard = useMemo(() => {
    if (selectedCardAddress === 'default') return undefined;
    return selectedCardAddress ? nfts?.[selectedCardAddress] : undefined;
  }, [selectedCardAddress, nfts]);

  const previewCard = selectedCardAddress === 'default' ? undefined : (selectedCard || currentCardNft);
  const isDefaultSelected = selectedCardAddress === 'default';

  const handleCardSelect = useLastCallback((address: string) => {
    setSelectedCardAddress(address);
  });

  const handleApplyCard = useLastCallback(() => {
    if (isDefaultSelected) {
      clearCardBackgroundNft();
    } else if (selectedCard) {
      setCardBackgroundNft({ nft: selectedCard });
    }
    closeCustomizeWalletModal();
  });

  const handleGetMoreCards = useLastCallback(() => {
    if (isMintingCardsAvailable && !isNftBuyingDisabled) {
      openMintCardModal();
    } else {
      void openUrl(MTW_CARDS_WEBSITE);
    }
  });

  const isApplyButtonDisabled = !isDefaultSelected
    && (!selectedCard || selectedCard.address === currentCardNft?.address);

  function renderCardsSelector() {
    return (
      <>
        <div className={styles.section}>
          <div className={styles.sectionSelectCard}>
            <h3 className={styles.sectionTitle}>
              {lang('Select the card stored in this wallet:')}
            </h3>

            <CardGrid
              cards={availableCardNfts!}
              selectedAddress={selectedCardAddress}
              onCardSelect={handleCardSelect}
              tokens={tokens}
              baseCurrency={baseCurrency}
              currencyRates={currencyRates}
            />
          </div>

          <p className={styles.helperTextOutside}>
            {lang(
              'This card will be installed for this wallet and will be displayed '
              + 'on the home screen and in the wallets list.',
            )}
          </p>
        </div>

        <div className={styles.section}>
          <h3 className={styles.sectionHeader}>
            {lang('Palette')}
          </h3>
          <AccentColorSelector
            accentColorIndex={accentColorIndex}
            nftAddresses={orderedNftAddresses}
            nftsByAddress={nfts}
            theme={theme}
            isViewMode={isViewMode}
            isMintingCardsAvailable={isMintingCardsAvailable}
            isNftBuyingDisabled={isNftBuyingDisabled}
            noUnlockButton
          />
          <p className={styles.helperTextOutside}>
            {lang('Get a unique MyTonWallet Card to unlock new palettes.')}
          </p>
        </div>
        <div className={styles.section}>
          <div className={styles.getMoreButton} onClick={handleGetMoreCards} role="button" tabIndex={0}>
            <span className={styles.getMoreText}>{lang('Get More Cards')}</span>
          </div>

          <p className={styles.helperTextOutside}>
            {lang('Browse MyTonWallet Cards available for purchase.')}
          </p>
        </div>
        <div className={styles.section}>
          <Button
            className={styles.applyButton}
            isPrimary
            isDisabled={isApplyButtonDisabled}
            onClick={handleApplyCard}
          >
            {isDefaultSelected ? lang('Reset Card') : lang('Apply Card')}
          </Button>
        </div>
      </>
    );
  }

  function renderLoading() {
    return (
      <div className={styles.section}>
        <div className={buildClassName(styles.sectionSelectCard, styles.loading)}>
          <Spinner />
        </div>
      </div>
    );
  }

  enum RenderingKey {
    Loading,
    CardsSelector,
    EmptyState,
  }

  const renderingKey = isLoading
    ? RenderingKey.Loading
    : hasCards ? RenderingKey.CardsSelector : RenderingKey.EmptyState;

  return (
    <Modal
      isOpen={isOpen}
      onClose={closeCustomizeWalletModal}
      dialogClassName={styles.modalDialog}
      nativeBottomSheetKey="customize-wallet"
      hasCloseButton
      forceFullNative
    >
      <ModalHeader
        className={styles.modalHeader}
        title={lang('Customize Wallet')}
        withNotch={isScrolled}
        onBackButtonClick={returnTo ? closeCustomizeWalletModal : undefined}
        onClose={returnTo ? undefined : closeCustomizeWalletModal}
      />

      <div
        className={buildClassName(modalStyles.transition, 'custom-scroll', styles.content)}
        onScroll={handleContentScroll}
      >
        <div className={styles.walletCardPreviews}>
          <WalletCardPreview
            account={account}
            tokens={tokens}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            previewCardNft={previewCard}
            variant="left"
          />

          <WalletCardPreview
            account={account}
            tokens={tokens}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            previewCardNft={previewCard}
            variant="middle"
          />

          <WalletCardPreview
            account={account}
            tokens={tokens}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            previewCardNft={previewCard}
            variant="right"
          />
        </div>

        <Transition
          name="semiFade"
          activeKey={renderingKey}
        >
          {renderingKey === RenderingKey.Loading && renderLoading()}
          {renderingKey === RenderingKey.CardsSelector && renderCardsSelector()}
          {renderingKey === RenderingKey.EmptyState && <EmptyState onGetFirstCard={handleGetMoreCards} />}
        </Transition>
      </div>
    </Modal>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = global.currentAccountId;
  if (!accountId) {
    return {
      theme: global.settings.theme,
      isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
    };
  }

  const account = selectAccount(global, accountId);
  const accountState = selectAccountState(global, accountId);
  const accountSettings = selectAccountSettings(global, accountId);
  const tokens = selectCurrentAccountTokens(global);
  const { config: { cardsInfo } = {} } = accountState || {};

  return {
    accountId,
    account,
    nfts: accountState?.nfts?.byAddress,
    orderedNftAddresses: accountState?.nfts?.orderedAddresses,
    currentCardNft: accountSettings?.cardBackgroundNft,
    accentColorIndex: accountSettings?.accentColorIndex,
    tokens,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    theme: global.settings.theme,
    isMintingCardsAvailable: Boolean(cardsInfo),
    isViewMode: global.accounts?.byId[accountId]?.type === 'view',
    isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
    returnTo: global.customizeWalletReturnTo,
  };
})(CustomizeWalletModal));
