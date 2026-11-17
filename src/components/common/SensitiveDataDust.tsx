import React, { type TeactNode } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Theme } from '../../global/types';

import useAppTheme from '../../hooks/useAppTheme';
import useCardController from '../../hooks/useCardController';
import useIsMotionDisabled from '../../hooks/useIsMotionDisabled';

import PrivacyDust from './PrivacyDust';

interface OwnProps {
  isHidden: boolean;
  width: number;
  height: number;
  className?: string;
  children: TeactNode;
}

interface StateProps {
  theme: Theme;
  animationLevel: number;
}

function SensitiveDataDust({
  isHidden,
  width,
  height,
  className,
  children,
  theme,
  animationLevel,
}: OwnProps & StateProps) {
  const appTheme = useAppTheme(theme);
  // There is no card, so the dust does not move away from a finger, and the text breaks up from its center
  const { controller } = useCardController();
  const isMotionDisabled = useIsMotionDisabled(animationLevel);

  return (
    <PrivacyDust
      isHidden={isHidden}
      isDisabled={isMotionDisabled}
      fieldSize={[width, height]}
      controller={controller}
      revision={appTheme}
    >
      <span className={className}>{children}</span>
    </PrivacyDust>
  );
}

export default withGlobal<OwnProps>((global): StateProps => {
  return {
    theme: global.settings.theme,
    animationLevel: global.settings.animationLevel,
  };
})(SensitiveDataDust);
