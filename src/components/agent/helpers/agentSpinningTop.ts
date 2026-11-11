import { requestForcedReflow, requestMeasure, requestMutation } from '../../../lib/fasterdom/fasterdom';
import { parseCssColor } from '../../../util/colors';
import {
  BOX_HALF_EXTENT, computeAgentSpinningTopTransform, getAgentExpansionShift, LEAN, RESTING_OFFSET_X, RESTING_OFFSET_Y,
  VIEW_PITCH,
} from './agentSpinningTopGeometry';
import {
  type AgentSpinningTopFrame,
  drawAgentSpinningTop,
  getAgentSpinningTopUnit,
  reportAgentSpinningTopFrameTime,
} from './agentSpinningTopRenderer';
import getCanAnimate from './getCanAnimate';
import { getOpaqueBackgroundColor } from './streamingTextColor';

interface AgentSpinningTopOptions {
  /** How fast the top spins relative to its regular speed */
  speed: number;
  /** Taps spin it up; a hold grows it threefold above everything, where a drag spins and tilts it */
  isTouchInteractive: boolean;
  /** A large top, as the empty chat's, stands on the ground, with a shadow or a glow under it and its reflection */
  shouldShowGround?: boolean;
  /** Shared with the top that takes this one's place, which goes on with its motion */
  handoff?: AgentSpinningTopHandoff;
}

/**
 * The Agent's state a top shows: thinking or writing an answer, or a run the user stopped while the Agent was thinking
 */
export type AgentSpinningTopState = 'idle' | 'thinking' | 'stopped';

/**
 * Where a top is in its motion, kept for the top that takes its place, as the run's indicator moves from the chat's
 * end into the answer's message
 */
export interface AgentSpinningTopHandoff {
  motion?: AgentSpinningTopMotion;
  savedAt?: number;
}

interface AgentSpinningTopMotion {
  elapsedSeconds: number;
  turn: number;
  precessionPhase: number;
  boost: number;
  coastSpin: number;
  coastDuration: number;
  thinkingBoost: number;
  pitchOffset: number;
  pitchVelocity: number;
  swayPhases: number[];
}

interface AgentSpinningTopController {
  /**
   * Thinking spins the top up; its end eases it back; a Stop while the Agent thinks grows it as a press does and knocks
   * it over a little while grown, and it rights itself. Where motion is reduced, the top stands still as ever.
   */
  setState: (state: AgentSpinningTopState) => void;
  destroy: NoneToVoidFunction;
}

// The top spins clockwise as seen from above, and its lean goes round the same way: against the positive sense of the
// transform's yaw and lean direction
const SPIN_SENSE = -1;
const TURN_PERIOD_S = 1.2;
const PRECESSION_PERIOD_S = 2.1;
const NOD_PERIOD_S = 1.35;
const NOD_AMPLITUDE = 0.12;
const HELD_LEAN_REDUCTION = 0.5;
const MAXIMUM_FRAME_S = 0.05;
const TAP_DURATION_MS = 250;
const TAP_MOVEMENT = 8;
const HOLD_DELAY_MS = 150;
const TAP_BOOST = 1;
const TAP_BOOST_GROWTH = 0.5;
const FLING_VELOCITY = 600;
// A fling spins the top as on iOS, without standing it up as taps do: this many radians a second more at this speed,
// from half of it to 1.6 times it, in the fling's direction, coasting down over this long
const FLING_SPIN = 39;
const FLING_FULL_VELOCITY = 1500;
const MINIMUM_FLING_SHARE = 0.5;
const MAXIMUM_FLING_SHARE = 1.6;
const FLING_COAST_S = 0.7;
// A drag let go while the finger still moves carries its spin on, up to this many radians a second, coasting down over
// this long
const RELEASE_SPIN_LIMIT = 5;
const RELEASE_COAST_S = 1.2;
const RELEASE_COAST_WINDOW_MS = 120;
const MINIMUM_COAST_SPIN = 0.001;
const MAXIMUM_BOOST = 12;
const BOOST_DECAY_S = 1.6;
const MINIMUM_BOOST = 0.001;
const EXPANDED_SCALE = 3;
const GROW_DURATION_S = 0.46;
const GROW_DAMPING = 5.6;
const GROW_FREQUENCY = 6.2;
const RELEASE_DAMPING = 4.2;
const RELEASE_FREQUENCY = 7;
const RELEASE_DURATION_S = 1.96;
/** The resting canvas reaches this share of the side past each edge, so the leaning top is never clipped */
const RESTING_CANVAS_MARGIN = 0.1;
// Where the threefold top can reach around its box's center, in model units, y up, however it is tilted, and the
// margin its canvas keeps around that for the springy overshoot
const EXPANDED_REACH_MIN_X = -1.18;
const EXPANDED_REACH_MAX_X = 0.92;
const EXPANDED_REACH_MIN_Y = -1.47;
const EXPANDED_REACH_MAX_Y = 0.82;
const EXPANDED_REACH_MARGIN = 0.1;
const MINIMUM_EXPANDED_CANVAS_SIDE = 160;
// The held top's body across, around its box's center in model units: the rim around the point, and the leaning
// stem to the right
const EXPANDED_BODY_REACH_MIN_X = -0.83;
const EXPANDED_BODY_REACH_MAX_X = 0.71;
// The pitch's sway, its spring, the nod a release gives it and how far a finger tilts it, in radians
const SWAY_SCALE = 0.45;
const SWAY_AMPLITUDE_A = 0.17;
const SWAY_AMPLITUDE_B = 0.10;
const SWAY_PERIOD_A_S = 5.3;
const SWAY_PERIOD_B_S = 8.9;
const PITCH_SPRING_FREQUENCY = 6 * Math.PI;
const PITCH_SPRING_DAMPING = 0.8;
const PITCH_SPRING_STEP_S = 1 / 120;
const PITCH_LIMIT = 1.1;
const RELEASE_NOD = 2.2;
const DRAG_SCALE = 220;
// The color behind the top is read again this often while it moves, as after the theme changes
const BACKDROP_REFRESH_MS = 1000;
// A top that is laid out but hidden, as on a screen under another, looks again this often whether it shows
const HIDDEN_RECHECK_MS = 300;
const VELOCITY_WINDOW_MS = 100;
const LIFTED_Z_INDEX = 10000;
// A top that comes this soon after another left the handoff takes over its motion
const HANDOFF_WINDOW_MS = 300;
// The film over the coating shows at full strength, as on iOS
const IRIDESCENCE = 1;
// How the top answers the Agent's state, as on iOS. Thinking spins it up this many times its own speed on top of it,
// over this long, and its end eases it back over this long; thinking also leans it this much further and turns its
// lean this much faster.
const THINKING_BOOST = 6;
const THINKING_RISE_S = 0.6;
const THINKING_FALL_S = 0.9;
const THINKING_LEAN = 0.3;
const THINKING_PRECESSION = 0.4;
// A Stop knocks the top over this far beyond its lean, landing and decaying this fast, and sets off a nutation
const KNOCK_TILT = 0.3;
const KNOCK_RISE_S = 0.05;
const KNOCK_DECAY_S = 0.55;
const WOBBLE_FREQUENCY = 3.2;
const WOBBLE_DECAY_S = 0.7;
const WOBBLE_LEAN = 0.05;
const WOBBLE_DIRECTION = 0.6;
const WOBBLE_PITCH = 0.08;
// The share of its spin the knock costs, how it comes back, and when the knock has settled
const KNOCK_SLOWDOWN = 0.55;
const SLOWDOWN_DECAY_S = 0.8;
const KNOCK_DURATION_S = 4;
// The exposure the motion blur stands for, and how far the top may lean at most
const EXPOSURE_S = 1 / 24;
const MAXIMUM_LEAN = 0.6;
// A top grown by a Stop shrinks back after this long
const STOP_GROWTH_MS = 1000;
// A large top's ground reaches this far below its point, in model units, and its body's shadow lies this far up its
// axis from the point
const GROUND_REACH_BELOW = 0.6;
const GROUND_BODY_HEIGHT = 0.53;
// How far a top on the ground's canvas reaches below its resting canvas, as a share of the top's side
const GROUND_EXTENSION = Math.max(
  0, -RESTING_OFFSET_Y + GROUND_REACH_BELOW - BOX_HALF_EXTENT * (1 + 2 * RESTING_CANVAS_MARGIN),
) / (2 * BOX_HALF_EXTENT);
const THROTTLED_FRAME_INTERVAL_MS = 1000 / 30;

const tops = new Set<SpinningTop>();
let isFrameRequested = false;
let frameInterval = 0;
let lastFrameAt = 0;
let themeObserver: MutationObserver | undefined;

/**
 * Moves and draws one spinning top in `root`, in 3D: a hollow shell of frosted glass in the Agent gradient that spins
 * on its point, its leaning axis going around as a top's does, and nods a little, as on iOS and Android. It moves only
 * while it is on screen; where motion is reduced it stands still, leaning right as the mark does.
 */
export function createAgentSpinningTop(
  root: HTMLElement,
  canvas: HTMLCanvasElement,
  options: AgentSpinningTopOptions,
): AgentSpinningTopController {
  const top = new SpinningTop(root, canvas, options);
  tops.add(top);
  observeTheme();
  // The top is drawn before it shows, rather than leaving its canvas empty for a frame
  requestForcedReflow(() => {
    const draw = top.measureFrame(performance.now(), true);
    if (top.needsFrame()) requestFrame();
    return draw;
  });

  return {
    setState: (state) => top.setState(state),
    destroy: () => {
      tops.delete(top);
      top.destroy();
      if (!tops.size) {
        themeObserver?.disconnect();
        themeObserver = undefined;
      }
    },
  };
}

// The glass shows the background of the new theme, also on a top that stands still
function observeTheme() {
  if (themeObserver) return;

  themeObserver = new MutationObserver(() => {
    tops.forEach((top) => top.invalidate());
    requestFrame();
  });
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
}

function requestFrame() {
  if (isFrameRequested) return;
  isFrameRequested = true;
  requestMeasure(runFrame);
}

// Every top measures in one measure phase and draws in the mutation phase that follows, once a frame
function runFrame() {
  isFrameRequested = false;
  if (!tops.size) return;

  const now = performance.now();
  if (now - lastFrameAt < frameInterval) {
    requestFrame();
    return;
  }
  lastFrameAt = frameInterval ? now - (now - lastFrameAt) % frameInterval : now;
  const draws: NoneToVoidFunction[] = [];
  tops.forEach((top) => {
    const draw = top.measureFrame(now);
    if (draw) draws.push(draw);
  });
  if (draws.length) {
    requestMutation(() => {
      const startedAt = performance.now();
      draws.forEach((draw) => draw());
      const shouldThrottle = reportAgentSpinningTopFrameTime(performance.now() - startedAt);
      if (shouldThrottle !== undefined) {
        frameInterval = shouldThrottle ? THROTTLED_FRAME_INTERVAL_MS : 0;
      }
    });
  }
  for (const top of tops) {
    if (top.needsFrame()) {
      requestFrame();
      break;
    }
  }
}

interface Touch {
  pointerId: number;
  startX: number;
  startY: number;
  startTime: number;
  x: number;
  y: number;
  isTap: boolean;
  samples: { time: number; x: number }[];
}

interface LiftedCanvas {
  canvas: HTMLCanvasElement;
  /** How far the grown top moves to keep off the window's sides, in CSS pixels */
  shift: number;
}

class SpinningTop {
  private readonly frame: AgentSpinningTopFrame & { rotation: Float32Array; backdrop: [number, number, number] } = {
    rotation: new Float32Array(16),
    originX: 0,
    originY: 0,
    pixelsPerUnit: 0,
    strength: 0,
    isDark: false,
    backdrop: [1, 1, 1],
    iridescence: IRIDESCENCE,
    sweep: 0,
    streaks: 0,
  };

  private readonly ground = {
    camera: new Float32Array(16),
    reflection: new Float32Array(16),
    bodyX: 0,
    bodyZ: 0,
  };

  // The top's lean and spin without the camera, and the ground's mirror, for the ground and the reflection
  private readonly tiltAndSpin = new Float32Array(16);

  private readonly mirroredTop = new Float32Array(16);

  // The Agent's state: the spin thinking adds, in multiples of the top's own speed, when the last knock came and
  // where it is this frame, and whether a Stop grew the top
  private isThinking = false;

  private thinkingBoost = 0;

  private knockAt?: number;

  private readonly knock = { tilt: 0, wobble: 0, slowdown: 0 };

  private isHeldByStop = false;

  private stopTimer?: number;

  // The motion, advanced frame by frame so that a spin-up changes its pace without a jump
  private lastFrameAt = 0;

  private elapsedSeconds = 0;

  private turn = 0;

  private precessionPhase = 0;

  private boost = 0;

  // A drag's or a fling's spin, in radians a second, coasting down over its own time
  private coastSpin = 0;

  private coastDuration = FLING_COAST_S;

  // The camera's pitch around its elevation: a slow sway, a nod when the held top is let go, and a finger's tilt
  private pitchOffset = 0;

  private pitchVelocity = 0;

  private dragPitch = 0;

  private swayPhases = [Math.random() * 2 * Math.PI, Math.random() * 2 * Math.PI];

  // A touch: how far the top has grown out of its place (0 at rest, 1 at three times its size)
  private grip = 0;

  private isHolding = false;

  private isExpanding = false;

  private expansionStartAt = 0;

  private expansionFrom = 0;

  private touch?: Touch;

  private holdTimer?: number;

  private lifted?: LiftedCanvas;

  private isIntersecting = false;

  // Whether the top has looked if it is in view; until then, it waits for that look rather than counting as hidden
  private hasLooked = false;

  private isShown = false;

  private side = 0;

  private hasDrawn = false;

  private backdropReadAt = -Infinity;

  private hiddenRecheckTimer?: number;

  private readonly intersectionObserver: IntersectionObserver;

  private readonly resizeObserver: ResizeObserver;

  constructor(
    private readonly root: HTMLElement,
    private readonly canvas: HTMLCanvasElement,
    private readonly options: AgentSpinningTopOptions,
  ) {
    this.takeHandoff();
    // A top on the ground reaches below its box, where its shadow and reflection lie
    if (options.shouldShowGround) canvas.style.height = `${(1 + 2 * RESTING_CANVAS_MARGIN + GROUND_EXTENSION) * 100}%`;
    this.intersectionObserver = new IntersectionObserver((entries) => {
      this.isIntersecting = Boolean(entries[entries.length - 1]?.isIntersecting);
      this.hasLooked = true;
      this.hasDrawn = false;
      requestFrame();
    });
    this.intersectionObserver.observe(root);
    this.resizeObserver = new ResizeObserver(() => {
      this.hasDrawn = false;
      requestFrame();
    });
    this.resizeObserver.observe(root);
    document.addEventListener('visibilitychange', this.handleVisibilityChange);

    if (!options.isTouchInteractive) return;

    root.addEventListener('pointerdown', this.handlePointerDown);
    root.addEventListener('pointermove', this.handlePointerMove);
    root.addEventListener('pointerup', this.handlePointerUp);
    root.addEventListener('pointercancel', this.handlePointerCancel);
    root.addEventListener('touchmove', this.handleTouchMove, { passive: false });
    root.addEventListener('contextmenu', this.handleContextMenu);
    // The top keeps its touches to itself, so that holding it does not open the menu of the message it is in, and
    // a tap on it does not end composing a chat
    root.addEventListener('mousedown', stopPropagation);
    root.addEventListener('touchstart', stopPropagation, { passive: true });
    root.addEventListener('click', stopPropagation);
  }

  destroy() {
    this.intersectionObserver.disconnect();
    this.resizeObserver.disconnect();
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    window.clearTimeout(this.holdTimer);
    window.clearTimeout(this.hiddenRecheckTimer);
    window.clearTimeout(this.stopTimer);
    const { root } = this;
    root.removeEventListener('pointerdown', this.handlePointerDown);
    root.removeEventListener('pointermove', this.handlePointerMove);
    root.removeEventListener('pointerup', this.handlePointerUp);
    root.removeEventListener('pointercancel', this.handlePointerCancel);
    root.removeEventListener('touchmove', this.handleTouchMove);
    root.removeEventListener('contextmenu', this.handleContextMenu);
    root.removeEventListener('mousedown', stopPropagation);
    root.removeEventListener('touchstart', stopPropagation);
    root.removeEventListener('click', stopPropagation);
    const lifted = this.lifted;
    this.lifted = undefined;
    if (lifted) requestMutation(() => lifted.canvas.remove());
  }

  setState(state: AgentSpinningTopState) {
    this.isThinking = state === 'thinking';
    // A top a Stop grew shrinks back with the next state, as when a question follows the Stop at once
    this.releaseStopHold();
    if (state === 'stopped' && getCanAnimate()) {
      this.knockAt = this.elapsedSeconds;
      // A Stop grows the top over what is around it, as a press does, and a second later it shrinks back
      if (!this.isHolding) {
        this.isHeldByStop = true;
        this.setHolding(true);
        this.stopTimer = window.setTimeout(() => this.releaseStopHold(), STOP_GROWTH_MS);
      }
    }
    requestFrame();
  }

  needsFrame() {
    if (!this.isShown) return false;
    return !this.hasDrawn || this.isExpanding || Boolean(this.lifted) || getCanAnimate();
  }

  /** Draws the top again, with the color behind it read anew */
  invalidate() {
    this.hasDrawn = false;
    this.backdropReadAt = -Infinity;
  }

  /**
   * Measures what this frame draws and returns the drawing, or nothing while the top is not on screen. The first
   * frame comes before the intersection observer has told whether the top is in view, so it looks itself.
   */
  measureFrame(now: number, isFirst = false): NoneToVoidFunction | undefined {
    if (isFirst && !this.hasLooked) {
      this.isIntersecting = this.getIsInViewport();
      this.hasLooked = true;
    }
    if (!this.hasLooked) return undefined;

    const wasShown = this.isShown;
    this.isShown = this.isIntersecting && !document.hidden && this.getIsVisibleByStyle();
    if (!this.isShown) {
      this.lastFrameAt = 0;
      if (wasShown || this.lifted) this.settleNow();
      // Hidden with its screen, as the chat list under a chat, it looks again later rather than on every frame
      if (this.isIntersecting && !document.hidden) this.scheduleHiddenRecheck();
      return undefined;
    }

    const isStill = !getCanAnimate();
    if (isStill && this.hasDrawn && !this.isExpanding && !this.lifted) return undefined;

    const rootRect = this.root.getBoundingClientRect();
    this.side = Math.min(rootRect.width, rootRect.height);
    if (this.side <= 0) return undefined;

    if (!this.hasDrawn || now - this.backdropReadAt > BACKDROP_REFRESH_MS) {
      this.readBackdrop();
      this.backdropReadAt = now;
    }

    this.updateExpansion(now);
    if (!isStill) this.advance(now);
    else this.lastFrameAt = 0;

    const pixelRatio = window.devicePixelRatio || 1;
    const canvasSide = Math.round(this.side * (1 + 2 * RESTING_CANVAS_MARGIN) * pixelRatio);
    const canvasHeight = this.options.shouldShowGround
      ? Math.round(this.side * (1 + 2 * RESTING_CANVAS_MARGIN + GROUND_EXTENSION) * pixelRatio)
      : canvasSide;
    const { lifted } = this;
    // Back in its place, the top draws on its resting canvas in the frame the canvas over the window goes
    const isSettled = this.grip === 0 && !this.isHolding && !this.isExpanding;
    if (lifted && isSettled) this.lifted = undefined;
    const liftedPlacement = lifted && !isSettled ? this.placeLifted(lifted, rootRect, pixelRatio) : undefined;
    // While the canvas over the window shows the top, the resting one is cleared
    const restingFrame = liftedPlacement ? undefined : this.composeFrame(pixelRatio, isStill);
    const liftedFrame = liftedPlacement ? this.composeFrame(pixelRatio, isStill, liftedPlacement) : undefined;
    // The canvas over the window fades with the top's place, as a row leaving with the grown top does
    const liftedOpacity = liftedPlacement ? getShownOpacity(this.root) : 1;
    this.hasDrawn = true;
    this.saveHandoff(now);

    return () => {
      if (this.canvas.width !== canvasSide || this.canvas.height !== canvasHeight) {
        this.canvas.width = canvasSide;
        this.canvas.height = canvasHeight;
      }
      drawAgentSpinningTop(this.canvas, restingFrame);
      if (!lifted) return;

      const { canvas } = lifted;
      if (!liftedPlacement || !liftedFrame) {
        canvas.remove();
        return;
      }
      if (canvas.width !== liftedPlacement.pixelWidth || canvas.height !== liftedPlacement.pixelHeight) {
        canvas.width = liftedPlacement.pixelWidth;
        canvas.height = liftedPlacement.pixelHeight;
        canvas.style.width = `${liftedPlacement.width}px`;
        canvas.style.height = `${liftedPlacement.height}px`;
      }
      canvas.style.transform = `translate(${liftedPlacement.left}px, ${liftedPlacement.top}px)`;
      canvas.style.opacity = String(liftedOpacity);
      drawAgentSpinningTop(canvas, liftedFrame, 'held');
    };
  }

  private getIsInViewport() {
    const { top, bottom, left, right } = this.root.getBoundingClientRect();
    return bottom > 0 && right > 0 && top < window.innerHeight && left < window.innerWidth;
  }

  // The top that takes this one's place goes on from where this one was last drawn
  private saveHandoff(now: number) {
    const { handoff } = this.options;
    if (!handoff) return;

    // One object serves every frame
    handoff.motion ??= {
      elapsedSeconds: 0,
      turn: 0,
      precessionPhase: 0,
      boost: 0,
      coastSpin: 0,
      coastDuration: FLING_COAST_S,
      thinkingBoost: 0,
      pitchOffset: 0,
      pitchVelocity: 0,
      swayPhases: [],
    };
    const { motion } = handoff;
    motion.elapsedSeconds = this.elapsedSeconds;
    motion.turn = this.turn;
    motion.precessionPhase = this.precessionPhase;
    motion.boost = this.boost;
    motion.coastSpin = this.coastSpin;
    motion.coastDuration = this.coastDuration;
    motion.thinkingBoost = this.thinkingBoost;
    motion.pitchOffset = this.pitchOffset;
    motion.pitchVelocity = this.pitchVelocity;
    motion.swayPhases = this.swayPhases;
    handoff.savedAt = now;
  }

  private takeHandoff() {
    const { handoff } = this.options;
    const motion = handoff?.motion;
    const { savedAt } = handoff ?? {};
    if (!handoff || !motion || savedAt === undefined || performance.now() - savedAt > HANDOFF_WINDOW_MS) return;

    handoff.motion = undefined;
    this.elapsedSeconds = motion.elapsedSeconds;
    this.turn = motion.turn;
    this.precessionPhase = motion.precessionPhase;
    this.boost = motion.boost;
    this.coastSpin = motion.coastSpin;
    this.coastDuration = motion.coastDuration;
    this.thinkingBoost = motion.thinkingBoost;
    this.pitchOffset = motion.pitchOffset;
    this.pitchVelocity = motion.pitchVelocity;
    this.swayPhases = motion.swayPhases;
    // The motion goes on over the time since it was last drawn, rather than pausing for a frame
    this.lastFrameAt = savedAt;
  }

  private getIsVisibleByStyle() {
    const { root } = this;
    return typeof root.checkVisibility === 'function' ? root.checkVisibility({ checkVisibilityCSS: true }) : true;
  }

  private scheduleHiddenRecheck() {
    if (this.hiddenRecheckTimer !== undefined) return;
    this.hiddenRecheckTimer = window.setTimeout(() => {
      this.hiddenRecheckTimer = undefined;
      this.hasDrawn = false;
      requestFrame();
    }, HIDDEN_RECHECK_MS);
  }

  private readonly handleVisibilityChange = () => {
    this.hasDrawn = false;
    requestFrame();
  };

  // The glass takes the background the top sits on as what is seen through it
  private readBackdrop() {
    const color = getOpaqueBackgroundColor(this.root);
    const parsed = color ? parseCssColor(color) : undefined;
    const { backdrop } = this.frame;
    if (parsed) {
      backdrop[0] = parsed.red / 255;
      backdrop[1] = parsed.green / 255;
      backdrop[2] = parsed.blue / 255;
    }
    this.frame.isDark = document.documentElement.classList.contains('theme-dark');
  }

  private advance(now: number) {
    const deltaSeconds = this.lastFrameAt === 0
      ? 0
      : Math.min(MAXIMUM_FRAME_S, Math.max(0, (now - this.lastFrameAt) / 1000));
    this.lastFrameAt = now;
    const { speed } = this.options;
    this.elapsedSeconds += deltaSeconds * speed;
    const thinkingTarget = this.isThinking ? THINKING_BOOST : 0;
    const easing = thinkingTarget > this.thinkingBoost ? THINKING_RISE_S : THINKING_FALL_S;
    this.thinkingBoost += (thinkingTarget - this.thinkingBoost) * (1 - Math.exp(-deltaSeconds / easing));
    if (this.knockAt !== undefined && this.elapsedSeconds - this.knockAt >= KNOCK_DURATION_S) this.knockAt = undefined;
    this.updateKnock();
    // One turn every 1.2 s at the regular speed, faster while spun up or thinking, slower for a while after a knock
    let turn = this.turn + (deltaSeconds * speed * this.getSpinMultiple()) / TURN_PERIOD_S;
    // A drag's or a fling's spin adds its own travel, either way, as it coasts down
    if (this.coastSpin) {
      const fade = Math.exp(-deltaSeconds / this.coastDuration);
      turn += (this.coastSpin * this.coastDuration * (1 - fade)) / (2 * Math.PI);
      this.coastSpin *= fade;
      if (Math.abs(this.coastSpin) < MINIMUM_COAST_SPIN) this.coastSpin = 0;
    }
    this.turn = ((turn % 1) + 1) % 1;
    // The faster a tap spins the top, the slower its lean goes around; thinking speeds it up
    const thinking = this.thinkingBoost / THINKING_BOOST;
    const precessionRate = (2 * Math.PI * speed * (1 + THINKING_PRECESSION * thinking)) / PRECESSION_PERIOD_S;
    this.precessionPhase = (this.precessionPhase + (precessionRate * deltaSeconds) / (1 + this.boost)) % (2 * Math.PI);
    this.boost *= Math.exp(-deltaSeconds / BOOST_DECAY_S);
    if (this.boost < MINIMUM_BOOST) this.boost = 0;
    this.advancePitch(deltaSeconds);
  }

  // The pitch follows its target on a stiff spring: the sway at rest, the finger's tilt while held
  private advancePitch(deltaSeconds: number) {
    let target: number;
    if (this.isHolding) {
      target = this.dragPitch / (1 + Math.abs(this.dragPitch) / PITCH_LIMIT);
    } else {
      const time = this.elapsedSeconds / this.options.speed;
      target = SWAY_SCALE * (
        SWAY_AMPLITUDE_A * Math.sin(((2 * Math.PI) / SWAY_PERIOD_A_S) * time + this.swayPhases[0])
        + SWAY_AMPLITUDE_B * Math.sin(((2 * Math.PI) / SWAY_PERIOD_B_S) * time + this.swayPhases[1])
      );
    }
    const stiffness = PITCH_SPRING_FREQUENCY * PITCH_SPRING_FREQUENCY;
    const damping = 2 * PITCH_SPRING_DAMPING * PITCH_SPRING_FREQUENCY;
    let remaining = deltaSeconds;
    while (remaining > 0) {
      const step = Math.min(remaining, PITCH_SPRING_STEP_S);
      this.pitchVelocity += ((target - this.pitchOffset) * stiffness - damping * this.pitchVelocity) * step;
      this.pitchOffset += this.pitchVelocity * step;
      remaining -= step;
    }
  }

  private composeFrame(
    pixelRatio: number,
    isStill: boolean,
    lifted?: { boxX: number; boxY: number },
  ): AgentSpinningTopFrame {
    const { frame } = this;
    const strength = Math.min(1, Math.max(0, this.grip));
    const unit = getAgentSpinningTopUnit(this.side) * (1 + 2 * this.grip);
    frame.pixelsPerUnit = unit * pixelRatio;
    // The box sits on the resting top, moving away from a screen edge as the top grows, wherever its canvas is
    frame.originX = ((lifted?.boxX ?? 0) + RESTING_OFFSET_X * unit) * pixelRatio;
    // The canvas of a top on the ground reaches further down, so the resting top stands higher in it
    const groundShift = this.options.shouldShowGround && !lifted ? (GROUND_EXTENSION * this.side) / 2 : 0;
    frame.originY = (-(lifted?.boxY ?? 0) + RESTING_OFFSET_Y * unit + groundShift) * pixelRatio;
    frame.strength = strength;
    const yaw = SPIN_SENSE * this.turn * 2 * Math.PI;
    let pitch = VIEW_PITCH;
    let lean = LEAN;
    let leanDirection = 0;
    if (isStill) {
      // A top that does not move leans to the right, as the mark does
      frame.sweep = 0;
      frame.streaks = 0;
    } else {
      const { knock } = this;
      const thinking = this.thinkingBoost / THINKING_BOOST;
      // A faster spin from taps stands the top up; thinking leans it further; held, it leans half as much
      const nod = 1 + NOD_AMPLITUDE * Math.sin((2 * Math.PI * this.elapsedSeconds) / NOD_PERIOD_S);
      const hold = 1 - strength * HELD_LEAN_REDUCTION;
      const signedLean = (LEAN * nod * (1 + THINKING_LEAN * thinking) * hold) / Math.sqrt(1 + this.boost)
        + KNOCK_TILT * knock.tilt + WOBBLE_LEAN * knock.wobble;
      const signedDirection = SPIN_SENSE * this.precessionPhase + WOBBLE_DIRECTION * knock.wobble;
      // A wobble past the upright leans the other way
      lean = Math.min(MAXIMUM_LEAN, Math.abs(signedLean));
      leanDirection = signedLean < 0 ? signedDirection + Math.PI : signedDirection;
      pitch = VIEW_PITCH + this.pitchOffset + WOBBLE_PITCH * knock.wobble;
      // The angle the body turns during an exposure, which blurs the patterns that turn with it, and the rings a fast
      // spin draws
      const rotationSpeed = (2 * Math.PI * this.options.speed) / TURN_PERIOD_S;
      const spinSpeed = Math.abs(rotationSpeed * this.getSpinMultiple() + this.coastSpin);
      frame.sweep = Math.min(Math.PI, spinSpeed * EXPOSURE_S);
      frame.streaks = 0.6 * Math.min(1, Math.max(0, (frame.sweep - 0.4) / 1.1));
    }
    computeAgentSpinningTopTransform(yaw, pitch, lean, leanDirection, frame.rotation);
    // The grown top keeps its ground and reflection, grown with it
    frame.ground = this.options.shouldShowGround ? this.composeGround(yaw, pitch, lean, leanDirection) : undefined;

    return frame;
  }

  // The ground through the top's point under the top, seen from the camera, and the top mirrored in it
  private composeGround(yaw: number, pitch: number, lean: number, leanDirection: number) {
    const { ground, tiltAndSpin, mirroredTop } = this;
    computeAgentSpinningTopTransform(0, pitch, 0, 0, ground.camera);
    computeAgentSpinningTopTransform(yaw, 0, lean, leanDirection, tiltAndSpin);
    // The mirror flips the height
    mirroredTop.set(tiltAndSpin);
    mirroredTop[1] = -mirroredTop[1];
    mirroredTop[5] = -mirroredTop[5];
    mirroredTop[9] = -mirroredTop[9];
    multiplyMatrices(ground.camera, mirroredTop, ground.reflection);
    // The body's shadow lies under the rim's center, up the leaning axis
    ground.bodyX = tiltAndSpin[4] * GROUND_BODY_HEIGHT;
    ground.bodyZ = tiltAndSpin[6] * GROUND_BODY_HEIGHT;

    return ground;
  }

  // The top's spin, in multiples of its own speed, with taps, thinking and a knock
  private getSpinMultiple() {
    return (1 + this.boost + this.thinkingBoost) * (1 - this.knock.slowdown);
  }

  // The knock's tilt, its wobble and the share of spin it costs this frame, all 0 once it has settled or without one
  private updateKnock() {
    const { knock } = this;
    const seconds = this.knockAt === undefined ? -1 : this.elapsedSeconds - this.knockAt;
    if (seconds < 0) {
      knock.tilt = 0;
      knock.wobble = 0;
      knock.slowdown = 0;
      return;
    }

    knock.tilt = Math.exp(-seconds / KNOCK_DECAY_S) * (1 - Math.exp(-seconds / KNOCK_RISE_S));
    knock.wobble = Math.exp(-seconds / WOBBLE_DECAY_S) * Math.sin(2 * Math.PI * WOBBLE_FREQUENCY * seconds);
    knock.slowdown = KNOCK_SLOWDOWN * Math.exp(-seconds / SLOWDOWN_DECAY_S);
  }

  // Pixels per model unit of the threefold top
  private getExpandedUnit() {
    return getAgentSpinningTopUnit(this.side) * EXPANDED_SCALE;
  }

  /** The canvas over the window covers wherever the threefold top can reach, so tilting it never clips it */
  private placeLifted(lifted: LiftedCanvas, rootRect: DOMRect, pixelRatio: number) {
    const unit = this.getExpandedUnit();
    const margin = 2 * EXPANDED_REACH_MARGIN;
    const width = Math.max(
      MINIMUM_EXPANDED_CANVAS_SIDE, Math.ceil((EXPANDED_REACH_MAX_X - EXPANDED_REACH_MIN_X + margin) * unit),
    );
    const height = Math.max(
      MINIMUM_EXPANDED_CANVAS_SIDE, Math.ceil((EXPANDED_REACH_MAX_Y - EXPANDED_REACH_MIN_Y + margin) * unit),
    );
    // The canvas's center relative to the resting top's, y down
    const offsetX = ((EXPANDED_REACH_MIN_X + EXPANDED_REACH_MAX_X) / 2) * unit + lifted.shift;
    const offsetY = (-(EXPANDED_REACH_MIN_Y + EXPANDED_REACH_MAX_Y) / 2) * unit;
    const centerX = rootRect.left + rootRect.width / 2 + offsetX;
    const centerY = rootRect.top + rootRect.height / 2 + offsetY;
    const strength = Math.min(1, Math.max(0, this.grip));

    return {
      width,
      height,
      pixelWidth: Math.round(width * pixelRatio),
      pixelHeight: Math.round(height * pixelRatio),
      left: centerX - width / 2,
      top: centerY - height / 2,
      boxX: lifted.shift * strength - offsetX,
      boxY: -offsetY,
    };
  }

  /**
   * How far the growing top moves away from a side of the window it would otherwise cross: a top near the edge grows
   * toward the middle, keeping 16 px from the side, or as far as it is from it already
   */
  private computeExpansionShift(rootRect: DOMRect) {
    const unit = this.getExpandedUnit();
    const center = rootRect.left + rootRect.width / 2;
    return getAgentExpansionShift(
      { start: rootRect.left, end: rootRect.right },
      { start: center + EXPANDED_BODY_REACH_MIN_X * unit, end: center + EXPANDED_BODY_REACH_MAX_X * unit },
      document.documentElement.clientWidth,
    );
  }

  private updateExpansion(now: number) {
    if (!this.isExpanding) return;

    const elapsed = Math.max(0, (now - this.expansionStartAt) / 1000);
    if (this.isHolding) {
      const progress = Math.min(1, elapsed / GROW_DURATION_S);
      const eased = progress * progress * (3 - 2 * progress);
      const settle = 1 - Math.exp(-GROW_DAMPING * eased) * (
        Math.cos(GROW_FREQUENCY * eased) + (GROW_DAMPING / GROW_FREQUENCY) * Math.sin(GROW_FREQUENCY * eased)
      );
      this.grip = this.expansionFrom + (1 - this.expansionFrom) * settle;
      if (progress === 1) {
        this.grip = 1;
        this.isExpanding = false;
      }
    } else {
      const spring = Math.exp(-RELEASE_DAMPING * elapsed) * Math.cos(RELEASE_FREQUENCY * elapsed);
      this.grip = this.expansionFrom * spring;
      if (elapsed >= RELEASE_DURATION_S) {
        this.grip = 0;
        this.isExpanding = false;
      }
    }
  }

  // A finger that took the top in the meantime keeps holding it
  private releaseStopHold() {
    window.clearTimeout(this.stopTimer);
    this.stopTimer = undefined;
    if (!this.isHeldByStop) return;

    this.isHeldByStop = false;
    if (!this.touch) this.setHolding(false);
  }

  // The top grows out of its place at once and springs back when let go
  private setHolding(shouldHold: boolean) {
    if (this.isHolding === shouldHold) return;

    const now = performance.now();
    this.updateExpansion(now);
    this.isHolding = shouldHold;
    this.isExpanding = true;
    this.expansionStartAt = now;
    this.expansionFrom = this.grip;
    if (shouldHold) this.lift();
    requestFrame();
  }

  // While it is grown, the top draws over the window, so that nothing clips it
  private lift() {
    if (this.lifted) return;

    const canvas = document.createElement('canvas');
    canvas.setAttribute('aria-hidden', 'true');
    Object.assign(canvas.style, {
      position: 'fixed',
      top: '0',
      left: '0',
      zIndex: String(LIFTED_Z_INDEX),
      pointerEvents: 'none',
    });
    const lifted: LiftedCanvas = { canvas, shift: 0 };
    this.lifted = lifted;
    requestMeasure(() => {
      if (this.lifted !== lifted) return;
      lifted.shift = this.computeExpansionShift(this.root.getBoundingClientRect());
      requestMutation(() => {
        if (this.lifted === lifted) document.body.appendChild(canvas);
      });
    });
  }

  // Back in its place, at once
  private settleNow() {
    window.clearTimeout(this.holdTimer);
    this.touch = undefined;
    this.isHolding = false;
    this.isExpanding = false;
    this.grip = 0;
    this.dragPitch = 0;
    const lifted = this.lifted;
    this.lifted = undefined;
    this.hasDrawn = false;
    if (lifted) requestMutation(() => lifted.canvas.remove());
  }

  private readonly handlePointerDown = (event: PointerEvent) => {
    if (this.touch || !getCanAnimate() || (event.pointerType === 'mouse' && event.button !== 0)) return;

    // The time is the page's own, on which the top also moves
    const now = performance.now();
    this.touch = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      startTime: now,
      x: event.clientX,
      y: event.clientY,
      isTap: true,
      samples: [{ time: now, x: event.clientX }],
    };
    // A touch stops a drag's or a fling's coast, as on iOS
    this.coastSpin = 0;
    try {
      this.root.setPointerCapture(event.pointerId);
    } catch {
      // A pointer that is already gone ends with its own events
    }
    // The top lifts after a short hold or a sideways move, so a scroll or a swipe back can start on it
    window.clearTimeout(this.holdTimer);
    this.holdTimer = window.setTimeout(() => this.setHolding(true), HOLD_DELAY_MS);
  };

  private readonly handlePointerMove = (event: PointerEvent) => {
    const { touch } = this;
    if (!touch || event.pointerId !== touch.pointerId) return;

    const dx = event.clientX - touch.startX;
    const dy = event.clientY - touch.startY;
    const distance = Math.hypot(dx, dy);
    if (distance > TAP_MOVEMENT) touch.isTap = false;
    if (!this.isHolding && distance > TAP_MOVEMENT) {
      window.clearTimeout(this.holdTimer);
      if (Math.abs(dx) > Math.abs(dy)) this.setHolding(true);
    }
    if (this.isHolding) {
      this.spinByFinger(event.clientX - touch.x);
      this.tiltByFinger(event.clientY - touch.y);
    }
    touch.x = event.clientX;
    touch.y = event.clientY;
    const now = performance.now();
    touch.samples.push({ time: now, x: event.clientX });
    while (touch.samples.length > 2 && now - touch.samples[0].time > VELOCITY_WINDOW_MS) {
      touch.samples.shift();
    }
  };

  private readonly handlePointerUp = (event: PointerEvent) => {
    const { touch } = this;
    if (!touch || event.pointerId !== touch.pointerId) return;

    window.clearTimeout(this.holdTimer);
    const now = performance.now();
    const first = touch.samples[0];
    const duration = Math.max(1, now - first.time);
    const velocity = ((event.clientX - first.x) / duration) * 1000;
    if (touch.isTap && now - touch.startTime <= TAP_DURATION_MS) {
      this.spinUp(TAP_BOOST + TAP_BOOST_GROWTH * this.boost);
    } else if (this.isHolding && Math.abs(velocity) > FLING_VELOCITY) {
      const share = Math.min(
        MAXIMUM_FLING_SHARE, Math.max(MINIMUM_FLING_SHARE, Math.abs(velocity) / FLING_FULL_VELOCITY),
      );
      this.coast(Math.sign(SPIN_SENSE * velocity) * FLING_SPIN * share, FLING_COAST_S);
    } else if (this.isHolding && now - touch.samples[touch.samples.length - 1].time <= RELEASE_COAST_WINDOW_MS) {
      const spin = (2 * Math.PI * SPIN_SENSE * velocity) / this.getFingerTurnWidth();
      this.coast(Math.min(RELEASE_SPIN_LIMIT, Math.max(-RELEASE_SPIN_LIMIT, spin)), RELEASE_COAST_S);
    }
    // Let go, the top nods as it springs back into place
    if (this.isHolding) this.pitchVelocity -= RELEASE_NOD;
    // A drag that ends away from the top clicks what holds both ends; that click is the drag's, not a tap there
    if (!touch.isTap) swallowNextClick();
    this.endTouch();
  };

  private readonly handlePointerCancel = (event: PointerEvent) => {
    if (!this.touch || event.pointerId !== this.touch.pointerId) return;

    window.clearTimeout(this.holdTimer);
    this.endTouch();
  };

  // A held top takes the finger: the list under it does not scroll
  private readonly handleTouchMove = (event: TouchEvent) => {
    if (this.isHolding && event.cancelable) event.preventDefault();
  };

  private readonly handleContextMenu = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
  };

  private endTouch() {
    this.touch = undefined;
    this.dragPitch = 0;
    this.setHolding(false);
  }

  private spinUp(amount: number) {
    this.boost = Math.min(MAXIMUM_BOOST, this.boost + amount);
    requestFrame();
  }

  private coast(spin: number, duration: number) {
    if (!Number.isFinite(spin)) return;
    this.coastSpin = spin;
    this.coastDuration = duration;
    requestFrame();
  }

  // A drag across the lifted top's width turns it once, its front following the finger
  private spinByFinger(dx: number) {
    const width = this.getFingerTurnWidth();
    if (width > 0) this.turn = (this.turn + (SPIN_SENSE * dx) / width + 1) % 1;
  }

  private getFingerTurnWidth() {
    return this.side * 0.92 * (1 + 2 * this.grip);
  }

  // A vertical drag tilts the held top toward or away from the viewer, less and less the further it goes
  private tiltByFinger(dy: number) {
    this.dragPitch += (dy * Math.PI) / DRAG_SCALE;
  }
}

function stopPropagation(event: Event) {
  event.stopPropagation();
}

function swallowNextClick() {
  function swallow(event: Event) {
    event.stopPropagation();
    event.preventDefault();
  }
  window.addEventListener('click', swallow, { capture: true, once: true });
  // The click comes with the release, if at all
  window.setTimeout(() => window.removeEventListener('click', swallow, { capture: true }));
}

// The opacity the element shows with, its own and its ancestors'
function getShownOpacity(element: HTMLElement) {
  let opacity = 1;
  for (let current: HTMLElement | null = element; current; current = current.parentElement) {
    opacity *= Number(getComputedStyle(current).opacity);
  }
  return opacity;
}

// `a` × `b` into `out`, all column-major
function multiplyMatrices(a: Float32Array, b: Float32Array, out: Float32Array) {
  for (let column = 0; column < 4; column++) {
    for (let row = 0; row < 4; row++) {
      let sum = 0;
      for (let k = 0; k < 4; k++) sum += a[k * 4 + row] * b[column * 4 + k];
      out[column * 4 + row] = sum;
    }
  }
}
