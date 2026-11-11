import React, {
  memo, useEffect, useRef,
} from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import buildClassName from '../../util/buildClassName';
import { REM } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';
import { useMediaQuery } from '../../hooks/useMediaQuery';

import AgentIcon from './AgentIcon';

import styles from './AgentDictationCircle.module.scss';

export type AgentDictationCircleMode = 'holding' | 'locked' | 'failed';

interface OwnProps {
  /** The middle of the microphone button, in the window */
  anchor: { x: number; y: number };
  mode: AgentDictationCircleMode;
  /** The circle came up only to show a failure, out of the microphone */
  isFailureOnly?: boolean;
  isClosing?: boolean;
  /** The input level, 0 to 1 */
  level: number;
  /**
   * How far the finger went toward cancelling (along the line) and up, in pixels. The circle reads it on every frame,
   * so that the finger's moves do not render the circle.
   */
  getDrag: () => { x: number; y: number };
  onFinish: NoneToVoidFunction;
  /** A locked recording is held with `onPause` and goes on with `onResume` */
  isPaused?: boolean;
  onPause?: NoneToVoidFunction;
  onResume?: NoneToVoidFunction;
  /** Whether the circle's middle covers the button at its anchor, called when that changes */
  onCoverChange?: (isCovering: boolean) => void;
}

/**
 * A pixel of Telegram's voice recording, which the circle and the microphone's gestures are measured in. It follows
 * the root font size, taken as 16 where it is not computed.
 */
export const DESIGN_PIXEL = (REM || 16) / 16;
const OUTER_MIN = 138 * DESIGN_PIXEL;
const OUTER_MAX = 259 * DESIGN_PIXEL;
const CENTRE = 99 * DESIGN_PIXEL;
const WAVE_POINT_COUNT = 8;
const WAVE_MIN_RADIUS = 1 / 1.1;
const WAVE_ANGLE_JITTER = Math.PI / 24;
// A cubic segment per eighth of a circle
const WAVE_HANDLE = (4 / 3) * Math.tan(Math.PI / (2 * WAVE_POINT_COUNT));
// The share of the smoothed level kept per frame at this frame rate
const LEVEL_SMOOTHING = 0.9;
const LEVEL_SMOOTHING_FRAME_RATE = 60;
// A late frame moves the waves on by at most this many seconds
const MAX_FRAME_STEP = 0.1;
// The waves change shape this many times a second in silence, and up to the sum of both as the voice peaks
const MORPH_RATE_MIN = 0.9;
const MORPH_RATE_GAIN = 3.1;
const FOLLOW_SHARE = 0.3;
const CANCEL_SHRINK_DISTANCE = 300 * DESIGN_PIXEL;
const CANCEL_MIN_SCALE = 0.4;
const LOCK_DISTANCE = 105 * DESIGN_PIXEL;
// The 44 px button under the circle's resting place
const ANCHOR_BUTTON_RADIUS = 22 * DESIGN_PIXEL;
// The waves' canvas, with room for the widest wave
const WAVES_SIZE = Math.ceil(OUTER_MAX * 1.05);
const WAVES_VIEW_BOX = `${-WAVES_SIZE / 2} ${-WAVES_SIZE / 2} ${WAVES_SIZE} ${WAVES_SIZE}`;

interface WavePoint {
  radius: number;
  angle: number;
}

/**
 * The circle over the microphone while the user dictates, with voice waves around it and the lock above it, after
 * Telegram's voice recording, as on mobile
 */
function AgentDictationCircle({
  anchor, mode, isFailureOnly, isClosing, level, getDrag, onFinish, isPaused, onPause, onResume, onCoverChange,
}: OwnProps) {
  const lang = useLang();
  const isReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const followRef = useRef<HTMLDivElement>();
  const outerRef = useRef<SVGPathElement>();
  const innerRef = useRef<SVGPathElement>();
  const lockRef = useRef<HTMLDivElement>();
  // A recording started hands-free has no lock to slide to
  const isStartedLocked = useRef(mode === 'locked').current;
  // The waves stand still where motion is reduced
  const isStill = isReducedMotion || getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN;
  const inputRef = useRef({
    level, getDrag, isStill, isClosing, onCoverChange,
  });
  inputRef.current = {
    level, getDrag, isStill, isClosing, onCoverChange,
  };

  useEffect(() => {
    let isRunning = true;
    let lastAt = Date.now();
    let smoothedLevel = 0;
    let loudestLevel = 0;
    let from = createWaveShape();
    let to = createWaveShape();
    let morphProgress = 0;
    let morphDuration = getMorphDuration(0);
    let innerFrom = createWaveShape();
    let innerTo = createWaveShape();
    const offset = { x: 0, y: 0 };
    let isCoveringAnchor: boolean | undefined;

    animate(() => {
      if (!isRunning) return false;
      const now = Date.now();
      const frameStep = Math.min(MAX_FRAME_STEP, (now - lastAt) / 1000);
      lastAt = now;
      const {
        level: currentLevel, getDrag: getCurrentDrag, isStill: isWaveStill, isClosing: isLeaving,
      } = inputRef.current;
      const currentDrag = getCurrentDrag();

      const keep = LEVEL_SMOOTHING ** (frameStep * LEVEL_SMOOTHING_FRAME_RATE);
      smoothedLevel = smoothedLevel * keep + currentLevel * (1 - keep);
      loudestLevel = Math.max(loudestLevel, currentLevel);
      if (!isWaveStill) {
        morphProgress += frameStep / morphDuration;
        if (morphProgress >= 1) {
          from = to;
          to = createWaveShape();
          innerFrom = innerTo;
          innerTo = createWaveShape();
          morphProgress = 0;
          morphDuration = getMorphDuration(loudestLevel);
          loudestLevel = 0;
        }
      }

      const ease = isWaveStill ? 0 : 0.5 - Math.cos(Math.PI * morphProgress) / 2;
      const outerDiameter = isWaveStill ? OUTER_MIN : OUTER_MIN + (OUTER_MAX - OUTER_MIN) * smoothedLevel;
      // The three circles grow by one ratio
      const innerDiameter = Math.sqrt(CENTRE * outerDiameter);
      outerRef.current?.setAttribute('d', buildWavePath(mixWaveShapes(from, to, ease), outerDiameter / 2));
      innerRef.current?.setAttribute('d', buildWavePath(mixWaveShapes(innerFrom, innerTo, ease), innerDiameter / 2));

      // A closing circle shrinks away where it is
      if (isLeaving) return true;

      // The circle closes a share of the way to the finger every frame, and shrinks as it goes toward cancelling
      offset.x += (currentDrag.x - offset.x) * FOLLOW_SHARE;
      offset.y += (currentDrag.y - offset.y) * FOLLOW_SHARE;
      const scale = 1 - (1 - CANCEL_MIN_SCALE) * Math.min(1, Math.abs(currentDrag.x) / CANCEL_SHRINK_DISTANCE);
      if (followRef.current) {
        followRef.current.style.transform = `translate(${offset.x}px, ${offset.y}px) scale(${scale})`;
      }
      const isCovering = Math.hypot(offset.x, offset.y) + ANCHOR_BUTTON_RADIUS <= (CENTRE / 2) * scale;
      if (isCovering !== isCoveringAnchor) {
        isCoveringAnchor = isCovering;
        inputRef.current.onCoverChange?.(isCovering);
      }
      lockRef.current?.style.setProperty('--lockness', String(getAgentDictationLockProgress(currentDrag.y)));

      return true;
    }, requestMutation);

    return () => {
      isRunning = false;
    };
  }, []);

  const glyph = mode === 'failed' ? 'failed' : mode === 'locked' ? 'locked' : 'holding';

  return (
    <div
      className={buildClassName(
        styles.root,
        mode === 'failed' && (isFailureOnly ? styles.failedFromMicrophone : styles.failed),
        mode === 'locked' && styles.locked,
        isStartedLocked && styles.startedLocked,
        isClosing && styles.closing,
      )}
      style={`--anchor-x: ${anchor.x}px; --anchor-y: ${anchor.y}px`}
    >
      <div ref={lockRef} className={styles.lock} aria-hidden>
        {/* The wallet's lock glyph with its shackle apart, so that the shackle stands open: its long right leg stays
            in the body, and closed it is the glyph again */}
        <svg className={styles.lockIcon} viewBox="0 0 768 768">
          <path
            className={styles.lockShackle}
            d={'M239.148 340V241.375c0-78.645 64.983-142.628 144.857-142.628c79.875 0 144.857 63.983 144.857 142.628'
              + 'V560H470.92V241.375c0-47.181-38.996-85.577-86.915-85.577c-47.918 0-86.914 38.396-86.914 85.577V340z'}
          />
          <path
            d={'M239.148 326.953H528.862q.563 0 1.124.01l1.12.028c36.499 1.224 65.163 32.195 63.249 68.954'
              + 'l-6.386 122.518c-2.24 42.156-3.981 64.62-12.059 82.664a115.2 115.2 0 0 1-63.613 60.386'
              + 'c-19.042 7.36-42.438 7.729-87.373 7.747H339.1c-42.349-.047-64.915-.607-83.386-7.747'
              + 'a115.2 115.2 0 0 1-63.613-60.386c-8.604-19.222-10.02-43.457-12.507-91.167l-5.938-114.015'
              + 'c-1.954-37.509 27.933-68.992 65.492-68.992z'}
          />
        </svg>
        <svg className={styles.lockChevron} viewBox="0 0 12 12">
          <path d="M3 7.5l3-3 3 3" />
        </svg>
      </div>
      {onPause && onResume && (
        // Once the recording locks, Pause takes the lock's place, as on Telegram's mobile apps. It holds the recording
        // as Telegram Web A's pause does, and turns into the microphone that resumes it.
        <button
          type="button"
          className={styles.pause}
          aria-label={lang(isPaused ? '$agent_voice_resume' : '$agent_voice_pause')}
          disabled={mode !== 'locked'}
          onClick={isPaused ? onResume : onPause}
        >
          <svg
            className={buildClassName(styles.pauseGlyph, styles.pauseBars, !isPaused && styles.pauseGlyphShown)}
            viewBox="0 0 20 20"
            aria-hidden
          >
            <path d="M7 5v10M13 5v10" />
          </svg>
          <AgentIcon
            name="microphone"
            className={buildClassName(styles.pauseGlyph, isPaused && styles.pauseGlyphShown)}
          />
        </button>
      )}
      <div ref={followRef} className={styles.follow}>
        <div className={styles.present}>
          <svg
            className={styles.waves}
            viewBox={WAVES_VIEW_BOX}
            style={`width: ${WAVES_SIZE}px; height: ${WAVES_SIZE}px`}
            aria-hidden
          >
            <path ref={outerRef} className={styles.outerWave} />
            <path ref={innerRef} className={styles.innerWave} />
          </svg>
          <button
            type="button"
            className={styles.centre}
            aria-label={lang('$agent_dictation_finish')}
            tabIndex={-1}
            disabled={mode !== 'locked'}
            onClick={onFinish}
          >
            <AgentIcon
              name="microphoneFilled"
              className={buildClassName(styles.glyph, styles.glyphMicrophone, glyph === 'holding' && styles.glyphShown)}
            />
            <svg className={buildClassName(styles.glyph, glyph === 'locked' && styles.glyphShown)} viewBox="0 0 24 24">
              <path d="M5 12.5l4.5 4.5L19 7.5" />
            </svg>
            <svg className={buildClassName(styles.glyph, glyph === 'failed' && styles.glyphShown)} viewBox="0 0 24 24">
              <path d="M6.5 6.5l11 11M17.5 6.5l-11 11" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * How far the finger has slid toward the lock, from 0 where it pressed to 1 at the lock, for a press dragged `dragY` up
 * (negative): the lock shortens and its shackle comes down in proportion, as on Telegram's mobile apps
 */
export function getAgentDictationLockProgress(dragY: number) {
  return Math.min(1, Math.abs(dragY) / LOCK_DISTANCE);
}

export default memo(AgentDictationCircle);

function getMorphDuration(loudestLevel: number) {
  return 1 / (MORPH_RATE_MIN + MORPH_RATE_GAIN * loudestLevel);
}

function createWaveShape(): WavePoint[] {
  return Array.from({ length: WAVE_POINT_COUNT }, () => ({
    radius: WAVE_MIN_RADIUS + Math.random() * (1 - WAVE_MIN_RADIUS),
    angle: (Math.random() - 0.5) * WAVE_ANGLE_JITTER,
  }));
}

function mixWaveShapes(from: WavePoint[], to: WavePoint[], progress: number): WavePoint[] {
  return from.map((point, index) => ({
    radius: point.radius + (to[index].radius - point.radius) * progress,
    angle: point.angle + (to[index].angle - point.angle) * progress,
  }));
}

// A closed curve through the points, with the handles of a circle of each point's radius
function buildWavePath(points: WavePoint[], nominalRadius: number) {
  const vertices = points.map(({ radius, angle }, index) => {
    const theta = (index / points.length) * 2 * Math.PI + angle;
    const pointRadius = radius * nominalRadius;
    return {
      x: Math.cos(theta) * pointRadius,
      y: Math.sin(theta) * pointRadius,
      tangentX: -Math.sin(theta) * pointRadius * WAVE_HANDLE,
      tangentY: Math.cos(theta) * pointRadius * WAVE_HANDLE,
    };
  });

  let path = `M${format(vertices[0].x)} ${format(vertices[0].y)}`;
  vertices.forEach((vertex, index) => {
    const next = vertices[(index + 1) % vertices.length];
    path += `C${format(vertex.x + vertex.tangentX)} ${format(vertex.y + vertex.tangentY)} `
      + `${format(next.x - next.tangentX)} ${format(next.y - next.tangentY)} ${format(next.x)} ${format(next.y)}`;
  });
  return `${path}Z`;
}

function format(value: number) {
  return value.toFixed(1);
}
