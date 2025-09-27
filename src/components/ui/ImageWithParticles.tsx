import type { ElementRef } from '../../lib/teact/teact';
import { memo } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { REM } from '../../util/windowEnvironment';

import Image from '../../components/ui/Image';

import styles from './ImageWithParticles.module.scss';

export const PARTICLE_HEIGHT = 12.75 * REM;
export const PARTICLE_LANDSCAPE_HEIGHT = 14.625 * REM;
export const PARTICLE_COLORS_GREEN = [30 / 255, 193 / 255, 96 / 255] as [number, number, number]; // #1EC160

interface OwnProps {
  imgPath: string;
  canvasRef: ElementRef<HTMLCanvasElement>;
  alt?: string;
  className?: string;
  onClick?: NoneToVoidFunction;
}

function ImageWithParticles({
  imgPath,
  alt,
  canvasRef,
  className,
  onClick,
}: OwnProps) {
  const isInteractive = Boolean(onClick);

  return (
    <div
      className={buildClassName(styles.root, className)}
      tabIndex={isInteractive ? -1 : undefined}
      role={isInteractive ? 'button' : undefined}
      onClick={onClick}
    >
      <canvas ref={canvasRef} className={styles.particles} />
      <div className={styles.logo}>
        <Image
          url={imgPath}
          isSlow
          alt={alt}
          imageClassName={styles.logoImg}
        />
      </div>
    </div>
  );
}

export default memo(ImageWithParticles);
