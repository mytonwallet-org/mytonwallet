import type { DiamondDrawState, DiamondScene } from './scene';

import { createDiamondScene, getFrameTime, TURN_DURATION } from './scene';
import { easeOutQuint, lerp } from './utils';

type Animation = {
  startTime: number;
  duration: number;
  isRepeated?: boolean;
  onUpdate: (progress: number) => void;
  onEnd?: () => void;
};

type Options = {
  // The first frame is on the canvas
  onReady?: () => void;
  // No WebGL 2, no usable GPU, a lost context or a failed model download; show a still or a Lottie instead
  onError?: () => void;
};

// Longer than a frame on 120 Hz screens and shorter than a frame on 100 Hz screens
const MIN_FRAME_INTERVAL = 9.5;

// Durations are in seconds of the scene clock. The clock stops while rendering is paused, so the diamond
// continues from the same angle instead of jumping ahead.
const IDLE_DELAY = 0.5;
const RELEASE_DURATION = 0.6;
const TAP_DURATION = 0.22;

const FULL_TURN = 360;
const OVERSHOOT_TENSION = 2;
const TAP_MAX_YAW = 10;
const TAP_MIN_ANGLE = 40;
const TAP_ANGLE_SPREAD = 30;
const TOUCH_SLOP = 8;
// Pointer movement is counted in device pixels, as on Android, so the diamond turns at the same speed
// as in the phone app on a screen with the same density
const DRAG_YAW_SPEED = 0.5;
const DRAG_PITCH_SPEED = 0.05;

// Draws the diamond into a square canvas whose `width` and `height` are its size in device pixels.
// Dragging turns the diamond, a tap tilts it towards the tapped point, and left alone it turns slowly.
// Returns a function that stops rendering and releases the WebGL context.
export function mountDiamond(canvas: HTMLCanvasElement, { onReady, onError }: Options = {}) {
  const handleError = () => onError?.();

  // Without a usable GPU, the browser renders WebGL on the CPU, which is far too slow for these shaders
  const gl = canvas.getContext('webgl2', { failIfMajorPerformanceCaveat: true });
  if (!gl) {
    handleError();
    return () => {};
  }

  let isDestroyed = false;
  let stop: (() => void) | undefined;

  createDiamondScene(gl, 'regular')
    .then((scene) => {
      if (isDestroyed) return;

      stop = startRendering(canvas, scene, () => onReady?.());
    })
    .catch(() => {
      if (!isDestroyed) handleError();
    });

  canvas.addEventListener('webglcontextlost', handleError);

  return () => {
    isDestroyed = true;
    stop?.();
    canvas.removeEventListener('webglcontextlost', handleError);
    gl.getExtension('WEBGL_lose_context')?.loseContext();
  };
}

function startRendering(canvas: HTMLCanvasElement, scene: DiamondScene, onReady: () => void) {
  const pixelRatio = window.devicePixelRatio || 1;
  const drawState: DiamondDrawState = {};
  // The canvas is square
  const viewport = { x: 0, y: 0, size: canvas.width };

  let frameId: number | undefined;
  let lastFrameTime: number | undefined;
  let time = 0;
  let isReady = false;

  // Rotation angles in degrees
  let yaw = 0;
  let pitch = 0;
  let animation: Animation | undefined;
  let isIdleEnabled = false;
  let isPressed = false;
  let isDragging = false;
  let startX = 0;
  let startY = 0;
  let lastX = 0;
  let lastY = 0;

  function render(now: number) {
    frameId = requestAnimationFrame(render);

    // Android draws the diamond at most 60 times per second. Skipping every other frame on 120 Hz screens
    // halves the GPU work, and the slow turn looks the same.
    if (lastFrameTime !== undefined && now - lastFrameTime < MIN_FRAME_INTERVAL) return;

    const frameTime = getFrameTime(now, lastFrameTime);
    lastFrameTime = now;
    time += frameTime;

    if (!isIdleEnabled && time >= IDLE_DELAY) {
      isIdleEnabled = true;
      startIdle();
    }

    updateAnimation();
    scene.draw(drawState, viewport, time, frameTime, convertToRadians(yaw), convertToRadians(pitch));

    if (!isReady) {
      isReady = true;
      onReady();
    }
  }

  function updateAnimation() {
    if (!animation) return;

    const current = animation;
    const progress = Math.max(0, time - current.startTime) / current.duration;
    if (current.isRepeated) {
      current.onUpdate(progress % 1);
      return;
    }

    current.onUpdate(Math.min(progress, 1));
    if (progress >= 1) {
      animation = undefined;
      current.onEnd?.();
    }
  }

  function startIdle() {
    if (!isIdleEnabled || isPressed || animation) return;

    const fromYaw = yaw;
    animation = {
      startTime: time,
      duration: TURN_DURATION,
      isRepeated: true,
      onUpdate: (progress) => {
        yaw = fromYaw + FULL_TURN * progress;
      },
    };
  }

  function release() {
    const fromYaw = yaw;
    const fromPitch = pitch;
    animation = {
      startTime: time,
      duration: RELEASE_DURATION,
      onUpdate: (progress) => {
        const ratio = 1 - easeOvershoot(progress);
        yaw = fromYaw * ratio;
        pitch = fromPitch * ratio;
      },
      onEnd: startIdle,
    };
  }

  function tiltTowards(x: number, y: number) {
    if (Math.abs(yaw) > TAP_MAX_YAW) return;

    const halfSize = Math.max(1, canvas.clientWidth / 2);
    const fromYaw = yaw;
    const fromPitch = pitch;
    const toYaw = ((halfSize - x) * getTapAngle()) / halfSize;
    const toPitch = ((halfSize - y) * getTapAngle()) / halfSize;
    animation = {
      startTime: time,
      duration: TAP_DURATION,
      onUpdate: (progress) => {
        const ratio = easeOutQuint(progress);
        yaw = lerp(fromYaw, toYaw, ratio);
        pitch = lerp(fromPitch, toPitch, ratio);
      },
      onEnd: release,
    };
  }

  function handlePointerDown(e: PointerEvent) {
    if (e.button !== 0) return;

    isPressed = true;
    isDragging = false;
    animation = undefined;
    startX = lastX = e.offsetX;
    startY = lastY = e.offsetY;
    canvas.setPointerCapture(e.pointerId);
  }

  function handlePointerMove(e: PointerEvent) {
    if (!isPressed) return;

    // On macOS, Ctrl+click opens a context menu that takes the button release, so `pointerup` never
    // reaches the canvas. Without this check, the diamond would keep following the mouse.
    if (!e.buttons) {
      handlePointerUp(e);
      return;
    }

    if (!isDragging) {
      if (Math.hypot(e.offsetX - startX, e.offsetY - startY) <= TOUCH_SLOP) return;
      isDragging = true;
    }

    yaw += (e.offsetX - lastX) * pixelRatio * DRAG_YAW_SPEED;
    pitch += (e.offsetY - lastY) * pixelRatio * DRAG_PITCH_SPEED;
    lastX = e.offsetX;
    lastY = e.offsetY;
  }

  function handlePointerUp(e: PointerEvent) {
    if (!isPressed) return;

    isPressed = false;
    release();
    if (!isDragging && e.type === 'pointerup') {
      tiltTowards(e.offsetX, e.offsetY);
    }
  }

  // A hidden tab stops drawing and continues from the same angle when it is shown again
  function updatePlayback() {
    if (document.hidden) {
      pause();
    } else {
      resume();
    }
  }

  function resume() {
    if (frameId !== undefined) return;

    lastFrameTime = undefined;
    frameId = requestAnimationFrame(render);
  }

  function pause() {
    if (frameId === undefined) return;

    cancelAnimationFrame(frameId);
    frameId = undefined;
  }

  document.addEventListener('visibilitychange', updatePlayback);
  canvas.addEventListener('pointerdown', handlePointerDown);
  canvas.addEventListener('pointermove', handlePointerMove);
  canvas.addEventListener('pointerup', handlePointerUp);
  canvas.addEventListener('pointercancel', handlePointerUp);

  updatePlayback();

  return () => {
    pause();
    document.removeEventListener('visibilitychange', updatePlayback);
    canvas.removeEventListener('pointerdown', handlePointerDown);
    canvas.removeEventListener('pointermove', handlePointerMove);
    canvas.removeEventListener('pointerup', handlePointerUp);
    canvas.removeEventListener('pointercancel', handlePointerUp);
  };
}

function getTapAngle() {
  return Math.random() * TAP_ANGLE_SPREAD + TAP_MIN_ANGLE;
}

function easeOvershoot(t: number) {
  const shifted = t - 1;
  return shifted * shifted * ((OVERSHOOT_TENSION + 1) * shifted + OVERSHOOT_TENSION) + 1;
}

function convertToRadians(degrees: number) {
  return (degrees * Math.PI) / 180;
}
