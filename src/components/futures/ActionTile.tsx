import React, { memo, useEffect } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Theme } from '../../global/types';

import { ANIMATED_STICKER_ICON_PX, ANIMATED_STICKER_ICON_SPEED } from '../../config';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useAppTheme from '../../hooks/useAppTheme';
import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Spinner from '../ui/Spinner';

import styles from './ActionTile.module.scss';

type IconKey = 'iconLong' | 'iconShort' | 'iconAdjust' | 'iconClose';

interface OwnProps {
  icon: IconKey;
  label: string;
  isDisabled?: boolean;
  /** The action prepares before it opens, and the tile shows a spinner instead of its icon meanwhile */
  isLoading?: boolean;
  onClick?: NoneToVoidFunction;
}

interface StateProps {
  theme: Theme;
}

/** The icon keeps the default accent of its animation file, as the whole Perps section does */
function ActionTile({
  icon, label, isDisabled, isLoading, theme, onClick,
}: OwnProps & StateProps) {
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];
  const [isAnimating, play, stop] = useFlag();

  // The spinner unmounts a playing icon before it reports the end, which would replay it once the spinner hides
  useEffect(() => {
    if (isLoading) stop();
  }, [isLoading, stop]);

  const handleClick = useLastCallback(() => {
    if (IS_TOUCH_ENV) {
      play();
    }
    onClick?.();
  });

  return (
    <Button
      isSimple
      isDisabled={isDisabled || isLoading}
      className={styles.root}
      onClick={handleClick}
      onMouseEnter={!IS_TOUCH_ENV && !isDisabled ? play : undefined}
    >
      {isLoading ? <Spinner className={styles.spinner} /> : (
        <AnimatedIconWithPreview
          play={isAnimating}
          size={ANIMATED_STICKER_ICON_PX}
          speed={ANIMATED_STICKER_ICON_SPEED}
          className={styles.icon}
          nonInteractive
          forceOnHeavyAnimation
          tgsUrl={stickerPaths[icon]}
          previewUrl={stickerPaths.preview[icon]}
          onEnded={stop}
        />
      )}
      <span className={styles.label}>{label}</span>
    </Button>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    theme: global.settings.theme,
  };
})(ActionTile));
