import type { RefObject } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Theme } from '../../global/types';
import type { ParticleConfig } from '../../util/particles';

import { ANIMATION_LEVEL_MIN } from '../../config';
import buildClassName from '../../util/buildClassName';

import useAppTheme from '../../hooks/useAppTheme';
import { useMediaQuery } from '../../hooks/useMediaQuery';

import ParticlesCanvas from '../ui/ParticlesCanvas';

import styles from './WelcomeParticles.module.scss';

const STAR_PATH = [
  'M5.45525 9.66128C5.31976 10.1129 4.68023 10.1129 4.54475 9.66128L4.30954 8.87721C3.85044 7.34678 2.65306 ',
  '6.14944 1.12261 5.69037L0.338737 5.45525C-0.112891 5.31979 -0.11292 4.68027 0.338696 4.54476L1.12302 4.30',
  '943C2.65324 3.85029 3.85041 2.65307 4.30951 1.12283L4.54476 0.33871C4.68025 -0.112904 5.31975 -0.112903 5',
  '.45524 0.33871L5.69049 1.12283C6.14959 2.65307 7.34676 3.85029 8.87698 4.30943L9.66131 4.54476C10.1129 4.',
  '68027 10.1129 5.31979 9.66126 5.45525L8.87739 5.69037C7.34694 6.14944 6.14956 7.34678 5.69045 8.87721L5.4',
  '5525 9.66128Z',
].join('');

const PARTICLE_CONFIG: Partial<ParticleConfig> = {
  width: 322,
  height: 204,
  centerShift: [0, 8],
  drift: {
    shouldScatter: true,
    hoverDensity: 2,
    pressDensity: 3,
    opacityMultiplier: 0.8,
    padding: 32,
    path: STAR_PATH,
    pathSize: 10,
    particles: [
      [27, 65, 10, 0.3],
      [51, 165, 10, 0.2],
      [288, 64, 10, 0.3],
      [227, 34, 10, 0.1],
      [303, 131, 6, 0.2],
      [308, 29, 6, 0.3],
      [54, 0, 6, 0.4],
      [316, 151, 6, 0.1],
      [310, 198, 6, 0.4],
      [21, 149, 6, 0.4],
      [65, 119, 6, 0.2],
      [0, 107, 6, 0.1],
      [67, 41, 15, 0.4],
      [135, 10, 15, 0.15],
      [10, 11, 15, 0.1],
      [246, 89, 15, 0.3],
      [262, 137, 15, 0.2],
      [189, 20, 10, 0.3],
    ],
  },
};
const LIGHT_COLOR: [number, number, number] = [44 / 255, 146 / 255, 240 / 255];
const DARK_COLOR: [number, number, number] = [70 / 255, 156 / 255, 236 / 255];

interface OwnProps {
  isActive?: boolean;
  interactionRef: RefObject<HTMLDivElement | undefined>;
  className?: string;
}

interface StateProps {
  shouldSkipAnimation: boolean;
  theme: Theme;
}

function WelcomeParticles({ isActive, interactionRef, className, shouldSkipAnimation, theme }: OwnProps & StateProps) {
  const appTheme = useAppTheme(theme);
  const isReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');

  return (
    <ParticlesCanvas
      isActive={isActive}
      isStatic={shouldSkipAnimation || isReducedMotion}
      interactionRef={interactionRef}
      color={appTheme === 'dark' ? DARK_COLOR : LIGHT_COLOR}
      particleConfig={PARTICLE_CONFIG}
      className={buildClassName(styles.root, className)}
    />
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => ({
  shouldSkipAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
  theme: global.settings.theme,
}))(WelcomeParticles));
