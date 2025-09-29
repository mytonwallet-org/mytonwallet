import type { RefObject, TeactNode } from '../../lib/teact/teact';
import { memo } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';
import Image from '../../components/ui/Image';

import styles from './ImageWithParticles.module.scss';

interface OwnProps {
  children?: TeactNode;

  imgPath: string;
  animationPath?: string;

  alt?: string;
  canvasRef: RefObject<HTMLCanvasElement | undefined>;

  isNft?: boolean;

  onClick?: () => void;
}

function ImageWithParticles({ children, imgPath, animationPath, alt, canvasRef, onClick, isNft }: OwnProps) {
  return (
    <div className={styles.container}>
      <canvas ref={canvasRef} className={styles.particles} />
      <div className={isNft ? styles.nft : styles.logo}>
        <div
          className={buildClassName(styles.logoContainer, isNft ? styles.logoNftContainer : styles.logoImgContainer)}
          tabIndex={-1}
          role="button"
          onClick={onClick}
        >
          {animationPath ? (
            <AnimatedIconWithPreview
              tgsUrl={animationPath}
              previewUrl={imgPath}
              size={124}
              className={styles.logoImg}
              play
              noLoop={false}
            />
          ) : (
            <Image
              url={imgPath}
              isSlow
              alt={alt ?? 't.me/push'}
              className={styles.logoImg}
            />
          )}
        </div>
        {children}
      </div>
    </div>
  );
}

export default memo(ImageWithParticles);
