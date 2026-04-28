import React, { memo } from '../../../../lib/teact/teact';

import type { AppTheme } from '../../../../global/types';

import { ANIMATED_STICKER_TINY_ICON_PX } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useShowTransition from '../../../../hooks/useShowTransition';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';

import styles from './Activity.module.scss';

const iconNamePrefix = 'iconClock';

type ClockPreviewKey = Extract<keyof typeof ANIMATED_STICKERS_PATHS.light.preview, `${typeof iconNamePrefix}${string}`>;
export type Color = ClockPreviewKey extends `${typeof iconNamePrefix}${infer C}` ? C : never;

interface OwnProps {
  isPending?: boolean;
  isError?: boolean;
  /** The error icon is always red */
  color?: Color;
  appTheme: AppTheme;
}

function ActivityStatusIcon({ isPending, isError, color = 'Gray', appTheme }: OwnProps) {
  const { shouldRender: shouldRenderClock, ref: clockRef } = useShowTransition({
    isOpen: isPending,
    withShouldRender: true,
  });

  // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
  const clockIconName = `${iconNamePrefix}${color}` as `${typeof iconNamePrefix}${Color}`;

  return (
    <>
      {isError && <i className={buildClassName(styles.iconError, 'icon-close-filled')} aria-hidden />}
      {shouldRenderClock && (
        <div ref={clockRef} className={styles.iconWaiting}>
          <AnimatedIconWithPreview
            play
            size={ANIMATED_STICKER_TINY_ICON_PX}
            nonInteractive
            noLoop={false}
            forceOnHeavyAnimation
            tgsUrl={ANIMATED_STICKERS_PATHS[appTheme][clockIconName]}
            previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview[clockIconName]}
          />
        </div>
      )}
    </>
  );
}

export default memo(ActivityStatusIcon);
