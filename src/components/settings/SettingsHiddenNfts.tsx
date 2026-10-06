import React, { memo, useCallback, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';

import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useScrolledState from '../../hooks/useScrolledState';

import AutoHiddenNft from './nfts/AutoHiddenNft';
import HiddenByUserNft from './nfts/HiddenByUserNft';
import HiddenNftList from './nfts/HiddenNftList';
import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  areUnverifiedNftsHidden?: boolean;
  orderedAddresses?: string[];
  byAddress?: Record<string, ApiNft>;
}

function SettingsHiddenNfts({
  isActive,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  areUnverifiedNftsHidden,
  orderedAddresses,
  byAddress,
  onBackClick,
}: OwnProps & StateProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onBackClick,
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

  const { hiddenByUserNfts, probablyScamNfts, unverifiedNfts } = useMemo(() => {
    const blacklistedNftAddressesSet = new Set(blacklistedNftAddresses);
    const hiddenByUser: ApiNft[] = [];
    const probablyScam: ApiNft[] = [];
    const unverified: ApiNft[] = [];

    for (const nft of nfts ?? []) {
      if (blacklistedNftAddressesSet.has(nft.address)) {
        hiddenByUser.push(nft);
      } else if (nft.isHidden) {
        probablyScam.push(nft);
      } else if (areUnverifiedNftsHidden && nft.isUnverified) {
        unverified.push(nft);
      }
    }

    return { hiddenByUserNfts: hiddenByUser, probablyScamNfts: probablyScam, unverifiedNfts: unverified };
  }, [nfts, blacklistedNftAddresses, areUnverifiedNftsHidden]);

  const whitelistedNftAddressesSet = useMemo(() => {
    return new Set(whitelistedNftAddresses);
  }, [whitelistedNftAddresses]);

  // `useLastCallback` would not fit here: `HiddenNftList` is memoized and re-renders its rows only
  // when the renderer identity changes, so it must change together with the captured values
  const renderUnverifiedNft = useCallback((nft: ApiNft, style: string) => (
    <AutoHiddenNft
      key={nft.address}
      nft={nft}
      section="unverified"
      isWhitelisted={whitelistedNftAddressesSet.has(nft.address)}
      style={style}
    />
  ), [whitelistedNftAddressesSet]);

  const renderProbablyScamNft = useCallback((nft: ApiNft, style: string) => (
    <AutoHiddenNft
      key={nft.address}
      nft={nft}
      section="scam"
      isWhitelisted={whitelistedNftAddressesSet.has(nft.address)}
      shouldConfirmUnhide
      style={style}
    />
  ), [whitelistedNftAddressesSet]);

  function renderHiddenByUserNfts() {
    return (
      <>
        <p className={styles.blockTitle}>{lang('Hidden By Me')}</p>
        <div className={buildClassName(styles.block, 'hidden-nfts-user')}>
          <HiddenNftList
            nfts={hiddenByUserNfts}
            isActive={isActive}
            renderNft={renderHiddenByUserNft}
          />
        </div>
      </>
    );
  }

  function renderUnverifiedNfts() {
    return (
      <>
        <p className={styles.blockTitle}>{lang('Unverified')}</p>
        <div className={buildClassName(styles.block, 'hidden-nfts-unverified')}>
          <HiddenNftList
            nfts={unverifiedNfts}
            isActive={isActive}
            renderNft={renderUnverifiedNft}
          />
        </div>
      </>
    );
  }

  function renderProbablyScamNfts() {
    return (
      <>
        <p className={styles.blockTitle}>{lang('Probably Scam')}</p>
        <div className={
          buildClassName(styles.block, styles.settingsBlockWithDescription, 'hidden-nfts-scam')
        }
        >
          <HiddenNftList
            nfts={probablyScamNfts}
            isActive={isActive}
            renderNft={renderProbablyScamNft}
          />
        </div>
        <p className={styles.blockDescription}>
          {lang('$settings_nft_probably_scam_description')}
        </p>
      </>
    );
  }

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Hidden NFTs')} isScrolled={isScrolled} onBackClick={onBackClick} />

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {Boolean(hiddenByUserNfts.length) && renderHiddenByUserNfts()}
        {Boolean(unverifiedNfts.length) && renderUnverifiedNfts()}
        {Boolean(probablyScamNfts.length) && renderProbablyScamNfts()}
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
    areUnverifiedNftsHidden: global.settings.areUnverifiedNftsHidden,
    orderedAddresses,
    byAddress,
  };
})(SettingsHiddenNfts));

function renderHiddenByUserNft(nft: ApiNft, style: string) {
  return <HiddenByUserNft key={nft.address} nft={nft} style={style} />;
}
