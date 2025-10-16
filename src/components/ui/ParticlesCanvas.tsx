import { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import type { ParticleConfig } from '../../util/particles';

import buildClassName from '../../util/buildClassName';
import { logDebugError } from '../../util/logs';
import { setupParticles } from '../../util/particles';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './ParticlesCanvas.module.scss';

interface OwnProps {
  isActive?: boolean;
  color: [number, number, number];
  particleConfig: Partial<ParticleConfig>;
  burstConfig?: Partial<ParticleConfig>;
  className?: string;
  onParticleClick?: NoneToVoidFunction;
}

// Default burst parameters that match original PARTICLE_BURST_PARAMS
const DEFAULT_BURST_PARAMS: Partial<ParticleConfig> = {
  particleCount: 90,
  selfDestroyTime: 3,
  accelerationFactor: 3,
  distanceLimit: 1,
};

const ParticlesCanvas = ({
  isActive = true,
  color,
  particleConfig,
  burstConfig = DEFAULT_BURST_PARAMS,
  className,
  onParticleClick,
}: OwnProps) => {
  const canvasRef = useRef<HTMLCanvasElement>();

  useLayoutEffect(() => {
    if (!isActive || !canvasRef.current) return;

    try {
      return setupParticles(canvasRef.current, {
        color,
        ...particleConfig,
      });
    } catch (err: any) {
      logDebugError('ParticlesCanvas initial effect', err);
    }
  }, [isActive, color, particleConfig]);

  const handleParticlesClick = useLastCallback(() => {
    if (!canvasRef.current) return;

    try {
      setupParticles(canvasRef.current, {
        color,
        ...particleConfig,
        ...burstConfig,
      });
    } catch (err: any) {
      logDebugError('ParticlesCanvas burst effect', err);
    }

    onParticleClick?.();
  });

  const canvasClassName = buildClassName(
    className || styles.particles,
    onParticleClick && 'interactive',
  );

  return (
    <canvas
      ref={canvasRef}
      className={canvasClassName}
      onClick={handleParticlesClick}
      aria-hidden
    />
  );
};

export default memo(ParticlesCanvas);
