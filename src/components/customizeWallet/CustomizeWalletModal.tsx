import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { Account, Theme, UserToken } from '../../global/types';

import { MTW_CARDS_COLLECTION, MTW_CARDS_WEBSITE } from '../../config';
import {
  selectAccount,
  selectAccountSettings,
  selectAccountState,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { openUrl } from '../../util/openUrl';
import { DEFAULT_CARD_ADDRESS } from './constants';

import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import AccentColorSelector from '../common/AccentColorSelector';
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
  areCardsLoading?: boolean;
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
  isNftBuyingDisabled,
  returnTo,
  areCardsLoading,
}: OwnProps & StateProps) {
  const {
    openCustomizeWalletModal,
    closeCustomizeWalletModal,
    setCardBackgroundNft,
    clearCardBackgroundNft,
    openMintCardModal,
    fetchNftsFromCollection,
    clearNftCollectionLoading,
  } = getActions();

  const lang = useLang();
  const [selectedCardAddress, setSelectedCardAddress] = useState<string>(DEFAULT_CARD_ADDRESS);

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  useEffectWithPrevDeps(([prevIsOpen]) => {
    if (isOpen && accountId) {
      fetchNftsFromCollection({ collection: { chain: 'ton', address: MTW_CARDS_COLLECTION } });
    }

    return () => {
      if (prevIsOpen && !isOpen) {
        clearNftCollectionLoading({ collection: { chain: 'ton', address: MTW_CARDS_COLLECTION } });
      }
    };
  }, [isOpen, accountId]);

  useEffectWithPrevDeps(([prevIsOpen]) => {
    if (isOpen && accountId) {
      setSelectedCardAddress(currentCardNft?.address ?? DEFAULT_CARD_ADDRESS); // Update selected card address to the current card when switching wallets
    }
    return () => {
      if (prevIsOpen && !isOpen) {
        setSelectedCardAddress(DEFAULT_CARD_ADDRESS);
      }
    };
  }, [isOpen, accountId, currentCardNft?.address]);

  const { availableCardNfts, cardsByAddress, cardsAddresses } = useMemo(() => {
    if (!nfts || !orderedNftAddresses || areCardsLoading) {
      return {
        availableCardNfts: undefined,
        cardsByAddress: undefined,
        cardsAddresses: undefined,
      };
    };

    const cardsAddresses = orderedNftAddresses.filter(
      (address) => nfts[address]?.collectionAddress === MTW_CARDS_COLLECTION && !nfts[address]?.isHidden,
    );

    const cardsByAddress = cardsAddresses.reduce<Record<string, ApiNft>>((result, address) => {
      result[address] = nfts[address];
      return result;
    }, {});

    return {
      cardsAddresses,
      cardsByAddress,
      availableCardNfts: Object.values(cardsByAddress || {}),
    };
  }, [nfts, orderedNftAddresses, areCardsLoading]);

  const isLoading = areCardsLoading || availableCardNfts === undefined;
  const hasCards = availableCardNfts && availableCardNfts.length > 0;

  const selectedCard = useMemo(() => {
    if (selectedCardAddress === DEFAULT_CARD_ADDRESS) return undefined;
    return selectedCardAddress ? nfts?.[selectedCardAddress] : undefined;
  }, [selectedCardAddress, nfts]);

  const previewCard = selectedCardAddress === DEFAULT_CARD_ADDRESS ? undefined : (selectedCard || currentCardNft);

  const handleCardSelect = useLastCallback((address: string) => {
    setSelectedCardAddress(address);
    if (address === DEFAULT_CARD_ADDRESS) {
      clearCardBackgroundNft();
    } else {
      const card = nfts![address];
      if (card) {
        setCardBackgroundNft({ nft: card });
      }
    }
  });

  const handleGetMoreCards = useLastCallback(() => {
    // Reset `returnTo` to avoid opening the previous modal above the browser
    openCustomizeWalletModal({ returnTo: undefined });
    closeCustomizeWalletModal();
    const callback = () => {
      if (isMintingCardsAvailable && !isNftBuyingDisabled) {
        openMintCardModal();
      } else {
        void openUrl(MTW_CARDS_WEBSITE);
      }
    };
    callback();
  });

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
            nftAddresses={cardsAddresses}
            nftsByAddress={cardsByAddress}
            theme={theme}
            isNftBuyingDisabled={isNftBuyingDisabled}
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
      hasCloseButton
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
            variant="right"
          />
        </div>

        <Transition
          name="semiFade"
          activeKey={renderingKey}
          slideClassName={styles.transitionSlide}
          className={styles.transition}
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
  const accountId = selectCurrentAccountId(global);
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

  const areCardsLoading = !accountState?.nfts?.isLoadedByAddress?.[MTW_CARDS_COLLECTION];

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
    areCardsLoading,
  };
})(CustomizeWalletModal));
