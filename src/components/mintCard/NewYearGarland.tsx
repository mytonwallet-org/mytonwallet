import React, {
  memo, useEffect, useMemo, useRef,
} from '../../lib/teact/teact';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { forceMutation } from '../../lib/fasterdom/stricterdom';
import buildClassName from '../../util/buildClassName';
import forceReflow from '../../util/forceReflow';
import { pause } from '../../util/schedulers';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import styles from './NewYearGarland.module.scss';

import garlandImageUrl from '../../assets/cards/mint-card-garland.png';

const RAW_BULBS = [
  { x: 8, y: 27, hex: '#FFFFAE' },
  { x: 43, y: 34, hex: '#FFB3B3' },
  { x: 74, y: 34, hex: '#FEFB0D' },
  { x: 102, y: 32, hex: '#0AFFF6' },
  { x: 129, y: 20, hex: '#EDA3FF' },
  { x: 150, y: 32, hex: '#FEFB0D' },
  { x: 179, y: 35, hex: '#FFFFAE' },
  { x: 206, y: 37, hex: '#FFB3B3' },
  { x: 232, y: 31, hex: '#0AFFF6' },
  { x: 254, y: 21, hex: '#EDA3FF' },
  { x: 280, y: 32, hex: '#FEFB0D' },
  { x: 310, y: 38, hex: '#FFB3B3' },
  { x: 342, y: 36, hex: '#EDA3FF' },
  { x: 370, y: 26, hex: '#FFFFAE' },
] as const;

const GLOW_BOX_SIZE = 32;
const ON_OPACITY = 0.6;
const DISSOLVE_MS = 10;
const GAP_MS = 10;
const VIEWBOX_WIDTH = 378;
const VIEWBOX_HEIGHT = 72;

const BULBS = RAW_BULBS.map((bulb) => ({
  ...bulb,
  fill: hexToRgb(bulb.hex),
}));

enum Opacities {
  On,
  Off,
}

function hexToRgb(hex: string) {
  const sanitized = hex.replace('#', '').trim();
  const number = parseInt(sanitized, 16);

  const r = (number >> 16) & 255;
  const g = (number >> 8) & 255;
  const b = number & 255;

  return `rgb(${r} ${g} ${b})`;
}

interface OwnProps {
  className?: string;
  animationLevel?: number;
}

function NewYearGarland({ className, animationLevel }: OwnProps) {
  const [isOn, markIsOn, unmarkIsOn] = useFlag(false);
  const circlesRef = useRef<(SVGCircleElement | undefined)[]>([]);
  const filterId = useMemo(() => `garlandGlowBlur-${Math.random().toString(36).slice(2, 8)}`, []);
  const shouldAnimate = animationLevel !== ANIMATION_LEVEL_MIN;
  const isAnimatingRef = useRef(false);
  const isCancelledRef = useRef(false);
  const hasPlayedInitialRef = useRef(false);

  useEffect(() => {
    isCancelledRef.current = false;
    setAll(isOn ? Opacities.On : Opacities.Off);

    if (!hasPlayedInitialRef.current) {
      hasPlayedInitialRef.current = true;
      if (!shouldAnimate) {
        setAll(Opacities.On);
        markIsOn();
      } else {
        void animateOn();
      }
    } else if (!shouldAnimate) {
      setAll(isOn ? Opacities.On : Opacities.Off);
    }

    return () => {
      isCancelledRef.current = true;
    };
  }, [shouldAnimate, isOn]);

  function setAll(target: Opacities) {
    const circles = circlesRef.current.filter(Boolean);
    if (!circles.length) return;

    forceMutation(() => {
      circles.forEach((circle) => {
        // Disable transition for instant changes
        const prev = circle.style.transition;
        circle.style.transition = 'none';
        circle.style.opacity = target === Opacities.On ? String(ON_OPACITY) : '0';
        // Force reflow then restore transition
        forceReflow(circle as any as HTMLElement);
        circle.style.transition = prev || `opacity ${DISSOLVE_MS}ms linear`;
      });
    }, circles);
  }

  const animateOn = useLastCallback(async () => {
    if (isAnimatingRef.current) return;
    isAnimatingRef.current = true;

    setAll(Opacities.Off);

    if (!shouldAnimate) {
      setAll(Opacities.On);
    } else {
      for (let i = 0; i < BULBS.length; i++) {
        if (isCancelledRef.current) break;
        const circle = circlesRef.current[i];
        if (!circle) continue;

        forceMutation(() => {
          circle.style.opacity = String(ON_OPACITY);
        }, circle);

        await pause(DISSOLVE_MS + GAP_MS);
        if (isCancelledRef.current) break;
      }
      // Normalize brightness to the last frame once the sweep is done.
      if (!isCancelledRef.current) {
        setAll(Opacities.On);
      }
    }

    if (!isCancelledRef.current) {
      markIsOn();
    }
    isAnimatingRef.current = false;
  });

  async function animateOff() {
    if (isAnimatingRef.current) return;
    isAnimatingRef.current = true;

    if (!shouldAnimate) {
      setAll(Opacities.Off);
    } else {
      for (let i = BULBS.length - 1; i >= 0; i--) {
        const circle = circlesRef.current[i];
        if (!circle) continue;
        forceMutation(() => {
          circle.style.opacity = '0';
        }, circle);
        // Give the dissolve a moment to play; stop early if turned back on.
        await pause(DISSOLVE_MS + GAP_MS);
        if (isCancelledRef.current) break;
      }
      if (!isCancelledRef.current) {
        setAll(Opacities.Off);
      }
    }

    if (!isCancelledRef.current) {
      unmarkIsOn();
    }
    isAnimatingRef.current = false;
  }

  const handleToggle = () => {
    if (isAnimatingRef.current) return;
    if (isOn) {
      void animateOff();
    } else {
      void animateOn();
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleToggle();
    }
  };

  return (
    <div
      className={buildClassName(styles.garland, className)}
      role="button"
      aria-pressed={isOn}
      tabIndex={0}
      onClick={handleToggle}
      onKeyDown={handleKeyDown}
    >
      <img
        src={garlandImageUrl}
        alt=""
        className={styles.garlandImage}
        aria-hidden
        loading="lazy"
        draggable={false}
      />

      <svg
        className={styles.garlandGlow}
        viewBox={`0 0 ${VIEWBOX_WIDTH} ${VIEWBOX_HEIGHT}`}
        role="presentation"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <filter id={filterId} x="-60%" y="-200%" width="220%" height="500%">
            <feGaussianBlur in="SourceGraphic" stdDeviation="10" />
          </filter>
        </defs>

        {BULBS.map((bulb, index) => (
          <circle
            key={index}
            cx={bulb.x}
            cy={bulb.y}
            r={GLOW_BOX_SIZE / 2}
            fill={bulb.fill}
            filter={`url(#${filterId})`}
            className={styles.garlandCircle}
            ref={(el) => {
              if (!circlesRef.current) {
                circlesRef.current = [];
              }
              circlesRef.current[index] = el;
            }}
          />
        ))}
      </svg>
    </div>
  );
}

export default memo(NewYearGarland);
