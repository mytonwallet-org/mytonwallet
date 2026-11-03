import { requestForcedReflow, requestMeasure, requestMutation } from '../../../lib/fasterdom/fasterdom';
import { parseCssColor } from '../../../util/colors';
import {
  computeAgentSpinningTopTransform, LEAN, RESTING_OFFSET_X, RESTING_OFFSET_Y, VIEW_PITCH,
} from './agentSpinningTopGeometry';
import {
  type AgentSpinningTopFrame,
  drawAgentSpinningTop,
  getAgentSpinningTopUnit,
  reportAgentSpinningTopFrameTime,
} from './agentSpinningTopRenderer';
import getCanAnimate from './getCanAnimate';
import { getOpaqueBackgroundColor } from './streamingTextColor';

export interface AgentSpinningTopOptions {
  /** How fast the top spins relative to its regular speed */
  speed: number;
  /** Taps spin it up; a hold grows it threefold above everything, where a drag spins and tilts it */
  isTouchInteractive: boolean;
  /** Shared with the top that takes this one's place, which goes on with its motion */
  handoff?: AgentSpinningTopHandoff;
}

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
  pitchOffset: number;
  pitchVelocity: number;
  swayPhases: number[];
}

export interface AgentSpinningTopController {
  destroy: NoneToVoidFunction;
}

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
const FLING_BOOST = 6;
const MAXIMUM_BOOST = 12;
const BOOST_DECAY_S = 1.6;
const MINIMUM_BOOST = 0.001;
const EXPANDED_SCALE = 3;
const SCREEN_EDGE_INSET = 16;
const GROW_DURATION_S = 0.46;
const GROW_DAMPING = 5.6;
const GROW_FREQUENCY = 6.2;
const RELEASE_DAMPING = 4.2;
const RELEASE_FREQUENCY = 7;
const RELEASE_DURATION_S = 1.96;
/** The resting canvas reaches this share of the side past each edge, so the leaning top is never clipped */
export const RESTING_CANVAS_MARGIN = 0.1;
// Where the threefold top can reach around its box's center, in model units, y up, however it is tilted, and the
// margin its canvas keeps around that for the springy overshoot
const EXPANDED_REACH_MIN_X = -1.22;
const EXPANDED_REACH_MAX_X = 0.96;
const EXPANDED_REACH_MIN_Y = -1.52;
const EXPANDED_REACH_MAX_Y = 0.82;
const EXPANDED_REACH_MARGIN = 0.1;
const MINIMUM_EXPANDED_CANVAS_SIDE = 160;
// The held top's body across, around its box's center in model units: the rim around the point, and the leaning
// stem to the right
const EXPANDED_BODY_REACH_MIN_X = -0.87;
const EXPANDED_BODY_REACH_MAX_X = 0.75;
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

function stopPropagation(event: Event) {
  event.stopPropagation();
}

function swallowNextClick() {
  const swallow = (event: Event) => {
    event.stopPropagation();
    event.preventDefault();
  };
  window.addEventListener('click', swallow, { capture: true, once: true });
  // The click comes with the release, if at all
  window.setTimeout(() => window.removeEventListener('click', swallow, { capture: true }));
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
  };

  // The motion, advanced frame by frame so that a spin-up changes its pace without a jump
  private lastFrameAt = 0;

  private elapsedSeconds = 0;

  private turn = 0;

  private precessionPhase = 0;

  private boost = 0;

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

    if (options.isTouchInteractive) {
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
  }

  destroy() {
    this.intersectionObserver.disconnect();
    this.resizeObserver.disconnect();
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    window.clearTimeout(this.holdTimer);
    window.clearTimeout(this.hiddenRecheckTimer);
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

    const dpr = window.devicePixelRatio || 1;
    const canvasSide = Math.round(this.side * (1 + 2 * RESTING_CANVAS_MARGIN) * dpr);
    const { lifted } = this;
    // Back in its place, the top draws on its resting canvas in the frame the canvas over the window goes
    const isSettled = this.grip === 0 && !this.isHolding && !this.isExpanding;
    if (lifted && isSettled) this.lifted = undefined;
    const liftedPlacement = lifted && !isSettled ? this.placeLifted(lifted, rootRect, dpr) : undefined;
    // While the canvas over the window shows the top, the resting one is cleared
    const restingFrame = liftedPlacement ? undefined : this.composeFrame(dpr, isStill);
    const liftedFrame = liftedPlacement ? this.composeFrame(dpr, isStill, liftedPlacement) : undefined;
    this.hasDrawn = true;
    this.saveHandoff(now);

    return () => {
      if (this.canvas.width !== canvasSide || this.canvas.height !== canvasSide) {
        this.canvas.width = canvasSide;
        this.canvas.height = canvasSide;
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
      elapsedSeconds: 0, turn: 0, precessionPhase: 0, boost: 0, pitchOffset: 0, pitchVelocity: 0, swayPhases: [],
    };
    const { motion } = handoff;
    motion.elapsedSeconds = this.elapsedSeconds;
    motion.turn = this.turn;
    motion.precessionPhase = this.precessionPhase;
    motion.boost = this.boost;
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
    // One turn every 1.2 s at the regular speed, faster while spun up
    this.turn = (this.turn + (deltaSeconds * speed * (1 + this.boost)) / TURN_PERIOD_S) % 1;
    this.precessionPhase = (
      this.precessionPhase + (2 * Math.PI * deltaSeconds * speed) / PRECESSION_PERIOD_S / (1 + this.boost)
    ) % (2 * Math.PI);
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
    dpr: number,
    isStill: boolean,
    lifted?: { boxX: number; boxY: number },
  ): AgentSpinningTopFrame {
    const { frame } = this;
    const strength = Math.min(1, Math.max(0, this.grip));
    const unit = getAgentSpinningTopUnit(this.side) * (1 + 2 * this.grip);
    frame.pixelsPerUnit = unit * dpr;
    // The box sits on the resting top, moving away from a screen edge as the top grows, wherever its canvas is
    frame.originX = ((lifted?.boxX ?? 0) + RESTING_OFFSET_X * unit) * dpr;
    frame.originY = (-(lifted?.boxY ?? 0) + RESTING_OFFSET_Y * unit) * dpr;
    frame.strength = strength;
    if (isStill) {
      // A top that does not move leans to the right, as the mark does
      computeAgentSpinningTopTransform(this.turn * 2 * Math.PI, VIEW_PITCH, LEAN, 0, frame.rotation);
    } else {
      // A faster spin stands the top up; held, it leans half as much
      const nod = 1 + NOD_AMPLITUDE * Math.sin((2 * Math.PI * this.elapsedSeconds) / NOD_PERIOD_S);
      const hold = 1 - strength * HELD_LEAN_REDUCTION;
      const lean = (LEAN * nod * hold) / Math.sqrt(1 + this.boost);
      computeAgentSpinningTopTransform(
        this.turn * 2 * Math.PI, VIEW_PITCH + this.pitchOffset, lean, this.precessionPhase, frame.rotation,
      );
    }

    return frame;
  }

  // Pixels per model unit of the threefold top
  private getExpandedUnit() {
    return getAgentSpinningTopUnit(this.side) * EXPANDED_SCALE;
  }

  /** The canvas over the window covers wherever the threefold top can reach, so tilting it never clips it */
  private placeLifted(lifted: LiftedCanvas, rootRect: DOMRect, dpr: number) {
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
      pixelWidth: Math.round(width * dpr),
      pixelHeight: Math.round(height * dpr),
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
    const windowWidth = document.documentElement.clientWidth;
    const center = rootRect.left + rootRect.width / 2;
    const bodyLeft = center + EXPANDED_BODY_REACH_MIN_X * unit;
    const bodyRight = center + EXPANDED_BODY_REACH_MAX_X * unit;
    const leftInset = Math.max(0, Math.min(SCREEN_EDGE_INSET, rootRect.left));
    const rightInset = Math.max(0, Math.min(SCREEN_EDGE_INSET, windowWidth - rootRect.right));
    if (bodyLeft < leftInset) return leftInset - bodyLeft;
    if (bodyRight > windowWidth - rightInset) return windowWidth - rightInset - bodyRight;
    return 0;
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
      this.spinUp(FLING_BOOST);
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

  // A drag across the lifted top's width turns it once
  private spinByFinger(dx: number) {
    const width = this.side * 0.92 * (1 + 2 * this.grip);
    if (width > 0) this.turn = (this.turn + dx / width + 1) % 1;
  }

  // A vertical drag tilts the held top toward or away from the viewer, less and less the further it goes
  private tiltByFinger(dy: number) {
    this.dragPitch += (dy * Math.PI) / DRAG_SCALE;
  }
}
