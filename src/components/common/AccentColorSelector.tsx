import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiNft } from '../../api/types';
import type { Theme } from '../../global/types';

import { IS_CORE_WALLET, MTW_CARDS_WEBSITE } from '../../config';
import { ACCENT_COLORS } from '../../util/accentColor/constants';
import buildClassName from '../../util/buildClassName';
import getAccentColorsFromNfts from '../../util/getAccentColorsFromNfts';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { openUrl } from '../../util/openUrl';

import useAppTheme from '../../hooks/useAppTheme';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Spinner from '../ui/Spinner';

import styles from './AccentColorSelector.module.scss';

interface OwnProps {
  accentColorIndex?: number;
  nftAddresses?: string[];
  nftsByAddress?: Record<string, ApiNft>;
  theme: Theme;
  isViewMode?: boolean;
  isMintingCardsAvailable?: boolean;
  isNftBuyingDisabled?: boolean;
  noUnlockButton?: boolean;
}

function AccentColorSelector({
  accentColorIndex,
  nftAddresses,
  nftsByAddress,
  theme,
  isViewMode,
  isMintingCardsAvailable,
  isNftBuyingDisabled,
  noUnlockButton,
}: OwnProps) {
  const {
    openMintCardModal,
    installAccentColorFromNft,
    clearAccentColorFromNft,
    showNotification,
  } = getActions();

  const lang = useLang();
  const [isAvailableAccentLoading, setIsAvailableAccentLoading] = useState(false);
  const [availableAccentColorIds, setAvailableAccentColorIds] = useState<number[]>(MEMO_EMPTY_ARRAY);
  const [nftByColorIndexes, setNftsByColorIndex] = useState<Record<number, ApiNft>>({});

  const appTheme = useAppTheme(theme);

  useEffect(() => {
    if (IS_CORE_WALLET) return;

    void (async () => {
      setIsAvailableAccentLoading(true);
      const result = await getAccentColorsFromNfts(nftAddresses, nftsByAddress);
      if (result) {
        setAvailableAccentColorIds(result.availableAccentColorIds);
        setNftsByColorIndex(result.nftsByColorIndex);
      } else {
        setAvailableAccentColorIds(MEMO_EMPTY_ARRAY);
        setNftsByColorIndex({});
      }
      setIsAvailableAccentLoading(false);
    })();
  }, [nftsByAddress, nftAddresses]);

  const sortedColors = useMemo(() => {
    return ACCENT_COLORS[appTheme]
      .map((color, index) => ({ color, index }))
      .sort((a, b) => {
        return Number(!availableAccentColorIds.includes(a.index))
          - Number(!availableAccentColorIds.includes(b.index));
      });
  }, [appTheme, availableAccentColorIds]);

  const handleAccentColorClick = useLastCallback((colorIndex?: number) => {
    const isLocked = colorIndex !== undefined ? !availableAccentColorIds.includes(colorIndex) : false;

    if (isLocked) {
      showNotification({ message: lang('Get a unique MyTonWallet Card to unlock new palettes.') });
    } else if (colorIndex === undefined) {
      clearAccentColorFromNft();
    } else {
      installAccentColorFromNft({ nft: nftByColorIndexes[colorIndex] });
    }
  });

  const handleUnlockNewPalettesClick = useLastCallback(() => {
    if (!isViewMode && isMintingCardsAvailable) {
      openMintCardModal();
    } else {
      void openUrl(MTW_CARDS_WEBSITE);
    }
  });

  function renderColorButton(color?: string, index?: number) {
    const isSelected = accentColorIndex === index;
    const isLocked = index !== undefined ? !availableAccentColorIds.includes(index) : false;

    return (
      <button
        key={color || 'default'}
        type="button"
        disabled={isSelected}
        style={color ? `--current-accent-color: ${color}` : undefined}
        className={buildClassName(styles.colorButton, isSelected && styles.colorButtonCurrent)}
        aria-label={lang('Change Palette')}
        onClick={() => handleAccentColorClick(index)}
      >
        {isAvailableAccentLoading && isLocked && <Spinner color="white" />}
        {!isAvailableAccentLoading && isLocked && (
          <i
            className={buildClassName(styles.iconLock, 'icon-lock', color === '#FFFFFF' && styles.iconLockInverted)}
            aria-hidden
          />
        )}
      </button>
    );
  }

  if (IS_CORE_WALLET || isNftBuyingDisabled) {
    return undefined;
  }

  return (
    <>
      <div className={styles.colorList}>
        {renderColorButton()}
        {sortedColors.map(({ color, index }) => renderColorButton(color, index))}
      </div>
      {!noUnlockButton && (
        <div
          className={styles.unlockButton}
          role="button"
          tabIndex={0}
          onClick={handleUnlockNewPalettesClick}
        >
          {lang('Unlock New Palettes')}
        </div>
      )}
    </>
  );
}

export default memo(AccentColorSelector);
