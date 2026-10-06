import { onFullyIdle } from '../../lib/teact/heavyAnimation';
import React, { memo, useEffect, useRef } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import { ANIMATION_LEVEL_MIN } from '../../config';
import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';

import styles from './GramDiamond.module.scss';

import blueDiamondTgs from '../../assets/lottie/blue_diamond.tgs';
import blueDiamondPreview from '../../assets/lottiePreview/blue_diamond.webp';

interface OwnProps {
  isOpen?: boolean;
  className?: string;
}

interface StateProps {
  noAnimation?: boolean;
}

// Matches `.root` in the stylesheet
const SIZE = 120;

// The 3D diamond turns on drag and tilts on tap. Without WebGL 2, a usable GPU or animations enabled,
// the Lottie diamond stands in its place.
function GramDiamond({ isOpen, className, noAnimation }: OwnProps & StateProps) {
  const canvasRef = useRef<HTMLCanvasElement>();
  const [isReady, markReady] = useFlag();
  const [isFailed, markFailed] = useFlag();
  const is3d = !noAnimation && !isFailed;

  useEffect(() => {
    if (!is3d) return undefined;

    let isDestroyed = false;
    let destroy: NoneToVoidFunction | undefined;

    // Creating a WebGL context blocks the main thread until the GPU process responds. During the modal
    // opening animation the GPU process is busy and the call takes tens of milliseconds, so the renderer
    // starts once the animation ends. A renderer chunk that fails to download leaves the Lottie in place.
    onFullyIdle(() => {
      if (isDestroyed) return;

      import('../../lib/blue-diamond/diamond').then(({ mountDiamond }) => {
        if (isDestroyed) return;

        destroy = mountDiamond(canvasRef.current!, { onReady: markReady, onError: markFailed });
      }).catch(markFailed);
    });

    return () => {
      isDestroyed = true;
      destroy?.();
    };
  }, [is3d]);

  if (!is3d) {
    return (
      <AnimatedIconWithPreview
        play={isOpen}
        size={SIZE}
        className={buildClassName(styles.root, className)}
        nonInteractive
        noLoop={false}
        tgsUrl={blueDiamondTgs}
        previewUrl={blueDiamondPreview}
      />
    );
  }

  const pixelSize = Math.round(SIZE * window.devicePixelRatio);

  // The still stands in until the model has rendered its first frame, then fades out under the canvas
  // fading in. The `capture-scroll` class keeps a vertical drag on the canvas from closing the modal.
  return (
    <div className={buildClassName(styles.root, className)}>
      <img
        src={blueDiamondPreview}
        alt=""
        draggable={false}
        className={buildClassName(styles.preview, isReady && styles.hidden)}
      />
      <canvas
        ref={canvasRef}
        width={pixelSize}
        height={pixelSize}
        className={buildClassName(styles.canvas, 'capture-scroll', isReady && styles.ready)}
      />
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    noAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
  };
})(GramDiamond));
