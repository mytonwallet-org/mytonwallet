import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';

import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import HiddenByUserNft from './nfts/HiddenByUserNft';
import ProbablyScamNft from './nfts/ProbablyScamNft';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  handleBackClick: NoneToVoidFunction;
  isInsideModal?: boolean;
}

interface StateProps {
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  orderedAddresses?: string[];
  byAddress?: Record<string, ApiNft>;
}

function SettingsHiddenNfts({
  isActive,
  handleBackClick,
  isInsideModal,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  orderedAddresses,
  byAddress,
}: OwnProps & StateProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: handleBackClick,
  });

  const {
    isScrolled,
    handleScroll: handleContentScroll,
  } = useScrolledState();

  const nfts = useMemo(() => {
    if (!orderedAddresses || !byAddress) {
      return undefined;
    }

    return orderedAddresses
      .map((address) => byAddress[address])
      .filter(Boolean);
  }, [
    byAddress, orderedAddresses,
  ]);

  const hiddenByUserNfts = useMemo(() => {
    const blacklistedNftAddressesSet = new Set(blacklistedNftAddresses);
    return nfts?.filter((nft) => blacklistedNftAddressesSet.has(nft.address));
  }, [nfts, blacklistedNftAddresses]);

  const probablyScamNfts = useMemo(() => {
    return nfts?.filter((nft) => nft.isHidden);
  }, [nfts]);

  const whitelistedNftAddressesSet = useMemo(() => {
    return new Set(whitelistedNftAddresses);
  }, [whitelistedNftAddresses]);

  const { isPortrait } = useDeviceScreen();
  const areSettingsInModal = !isPortrait || IS_ELECTRON;

  function renderHiddenByUserNfts() {
    return (
      <>
        <p className={styles.blockTitle}>{lang('Hidden By Me')}</p>
        <div className={buildClassName(styles.block, !areSettingsInModal && 'hidden-nfts-user')}>
          {hiddenByUserNfts!.map((nft) => <HiddenByUserNft key={nft.address} nft={nft} />)}
        </div>
      </>
    );
  }

  function renderProbablyScamNfts() {
    return (
      <>
        <p className={styles.blockTitle}>{lang('Probably Scam')}</p>
        <div className={
          buildClassName(styles.block, styles.settingsBlockWithDescription, !areSettingsInModal && 'hidden-nfts-scam')
        }
        >
          {
            probablyScamNfts!.map(
              (nft) => (
                <ProbablyScamNft
                  key={nft.address}
                  nft={nft}
                  isWhitelisted={whitelistedNftAddressesSet.has(nft.address)}
                />
              ),
            )
          }
        </div>
        <p className={styles.blockDescription}>
          {lang('$settings_nft_probably_scam_description')}
        </p>
      </>
    );
  }

  return (
    <div className={styles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('Hidden NFTs')}
          withNotch={isScrolled}
          onBackButtonClick={handleBackClick}
          className={styles.modalHeader}
        />
      ) : (
        <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={handleBackClick} className={styles.headerBack}>
            <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={styles.headerTitle}>{lang('Hidden NFTs')}</span>
        </div>
      )}

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {Boolean(hiddenByUserNfts?.length) && renderHiddenByUserNfts()}
        {Boolean(probablyScamNfts?.length) && renderProbablyScamNfts()}
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
  } = selectCurrentAccountState(global) ?? {};
  const {
    orderedAddresses,
    byAddress,
  } = selectCurrentAccountState(global)?.nfts ?? {};
  return {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    orderedAddresses,
    byAddress,
  };
})(SettingsHiddenNfts));
