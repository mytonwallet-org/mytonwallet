import { suppressStrict } from '../lib/fasterdom/fasterdom';

const DEFAULT_DURATION = 4;
const FADE_IN_FRACTION = 0.1;
const FADE_OUT_START = 0.65;
const FADE_OUT_FRACTION = 0.35;
const MAX_FADE_OUT_SLOPE = 3;
const MIN_SCALE = 0.75;
const SCALE_GROWTH = 0.25;
const MAX_DENSITY = 3;
const SCATTER_FADE_IN_TIME = 0.25;
const SCATTER_FADE_OUT_TIME = 1;
const BURST_FADE_IN_TIME = 0.05;
const SCATTER_MIN_RADIUS = 55;
const SCATTER_RADIUS_RANGE = 15;
const BURST_MIN_RADIUS = 5;
const BURST_RADIUS_RANGE = 45;
const SCATTER_MIN_TRAVEL = 0.5;
const SCATTER_TRAVEL_RANGE = 0.5;
const SCATTER_TRAVEL_MULTIPLIER = 0.45;
const SCATTER_MIN_OPACITY = 0.1;
const SCATTER_OPACITY_RANGE = 0.6;
const SCATTER_MIN_DURATION = 3;
const SCATTER_DURATION_RANGE = 2;
const EXTRA_MARGIN_X = 12;
const EXTRA_MARGIN_Y = 8;
const EXTRA_SEED_X = 0.754877666;
const EXTRA_SEED_Y = 0.569840296;
const EXTRA_SEED_ANGLE = 0.618033989;
const EXTRA_SEED_TRAVEL = 0.414213562;
const EXTRA_ANGLE_RANGE = 0.8;
const EXTRA_MIN_TRAVEL = 0.65;
const EXTRA_TRAVEL_RANGE = 0.7;
const DRIFT_DISTANCE_DIVISOR = 10;
const SCATTER_DISTANCE_DIVISOR = 4;
const SCATTER_DECELERATION = 3;
const EDGE_FADE_DISTANCE = 50;
const MAX_COLOR_CHANNEL = 255;
const MILLISECONDS_PER_SECOND = 1000;
const MAX_FRAME_TIME = 0.05;
const DEFAULT_PRESS_SPEED = 6;
const DEFAULT_HOVER_SPEED = 3;
const ACCELERATION_TIME = 0.18;
const DECELERATION_TIME = 0.55;
const SPEED_THRESHOLD = 0.005;
const PRESS_BOOST_DURATION = 180;
const BURST_COUNT = 5;

type ParticlePlacement = readonly [x: number, y: number, size: number, opacity: number];

export interface DriftParticleConfig {
  particles: readonly ParticlePlacement[];
  path: string;
  pathSize: number;
  duration?: number;
  fadeInTime?: number;
  fadeOutTime?: number;
  hoverSpeed?: number;
  pressSpeed?: number;
  hoverDensity?: number;
  pressDensity?: number;
  opacityMultiplier?: number;
  padding?: number;
  shouldScatter?: boolean;
}

export interface ParticleInteraction {
  target?: HTMLElement;
  isStatic?: boolean;
}

interface DriftParticleState {
  scatter?: ScatterParticle;
  progress: number;
  opacity: number;
  fadeInAge: number;
  fadeOutAge?: number;
  fadeOutOpacity: number;
  fadeOutStart: number;
  fadeOutSlope: number;
  isWaiting: boolean;
}

interface ScatterParticle {
  angle: number;
  radius: number;
  travel: number;
  opacity: number;
  duration: number;
  isBurst: boolean;
}

interface DriftParticleStream {
  baseCount: number;
  particles: DriftParticleState[];
  timeUntilNext: number;
  nextIndex: number;
}

export function setupDriftParticles(
  canvas: HTMLCanvasElement,
  config: DriftParticleConfig,
  width: number,
  height: number,
  color: readonly [number, number, number],
  centerShift: readonly [number, number],
  { target, isStatic }: ParticleInteraction,
) {
  const context = canvas.getContext('2d');
  if (!context) return () => {};

  const path = new Path2D(config.path);
  const pixelRatio = window.devicePixelRatio || 1;
  const padding = config.padding ?? 0;
  const canvasWidth = width + padding * 2;
  const canvasHeight = height + padding * 2;
  suppressStrict(() => {
    canvas.width = Math.round(canvasWidth * pixelRatio);
    canvas.height = Math.round(canvasHeight * pixelRatio);
    canvas.style.width = `${canvasWidth}px`;
    canvas.style.height = `${canvasHeight}px`;
  });

  let frameId: number | undefined;
  let lastTime: number | undefined;
  const stream = createDriftParticleStream(config.particles.length, config.duration, config.shouldScatter);
  let speed = 1;
  let density = 1;
  let isHovered = false;
  let pressedPointer: number | undefined;
  let boostUntil = 0;
  let isDestroyed = false;

  function draw() {
    context!.setTransform(pixelRatio, 0, 0, pixelRatio, padding * pixelRatio, padding * pixelRatio);
    context!.clearRect(-padding, -padding, canvasWidth, canvasHeight);
    context!.fillStyle = `rgb(${color.map((channel) => Math.round(channel * MAX_COLOR_CHANNEL)).join(',')})`;
    stream.particles.forEach((particle, index) => {
      const [baseX, baseY, size, opacity] = config.particles[index % config.particles.length];
      const isExtra = index >= config.particles.length;
      const seed = index - config.particles.length + 1;
      const x = isExtra ? EXTRA_MARGIN_X + ((0.5 + seed * EXTRA_SEED_X) % 1) * (width - EXTRA_MARGIN_X * 2) : baseX;
      const y = isExtra ? EXTRA_MARGIN_Y + ((0.5 + seed * EXTRA_SEED_Y) % 1) * (height - EXTRA_MARGIN_Y * 2) : baseY;
      const angle = isExtra ? ((seed * EXTRA_SEED_ANGLE) % 1 - 0.5) * EXTRA_ANGLE_RANGE : 0;
      const travel = isExtra ? EXTRA_MIN_TRAVEL + ((seed * EXTRA_SEED_TRAVEL) % 1) * EXTRA_TRAVEL_RANGE : 1;
      const sample = isStatic
        ? { progress: 0.5, scale: 1, opacity: 1 }
        : sampleDriftParticle(particle);
      const offset = (sample.progress * 2 - 1) / DRIFT_DISTANCE_DIVISOR;
      const originX = x - width / 2 - centerShift[0];
      const originY = y - height / 2 - centerShift[1];
      const cosine = Math.cos(angle);
      const sine = Math.sin(angle);
      const offsetX = (originX * cosine - originY * sine) * offset * travel;
      const offsetY = (originX * sine + originY * cosine) * offset * travel;
      const scatter = !isStatic ? particle.scatter : undefined;
      const progress = particle.progress;
      const distance = scatter
        ? scatter.radius + (width + height) / SCATTER_DISTANCE_DIVISOR * scatter.travel * progress
        * (1 + SCATTER_DECELERATION * Math.exp(-SCATTER_DECELERATION * progress)) : 0;
      const drawX = scatter ? width / 2 + centerShift[0] + Math.cos(scatter.angle) * distance : x + size / 2 + offsetX;
      const drawY = scatter ? height / 2 + centerShift[1] + Math.sin(scatter.angle) * distance : y + size / 2 + offsetY;
      const edgeFade = scatter
        ? Math.max(0, Math.min(1, Math.min(drawX + padding, width + padding - drawX,
          drawY + padding, height + padding - drawY) / EDGE_FADE_DISTANCE)) : 1;
      const scale = size * (scatter ? 1 : sample.scale) / config.pathSize;
      context!.save();
      context!.translate(drawX, drawY);
      context!.scale(scale, scale);
      context!.translate(-config.pathSize / 2, -config.pathSize / 2);
      context!.globalAlpha = Math.min(1, (scatter?.opacity ?? opacity) * (config.opacityMultiplier ?? 1))
        * sample.opacity * edgeFade;
      context!.fill(path);
      context!.restore();
    });
  }

  function tick(now: number) {
    const elapsed = lastTime === undefined ? 0 : Math.min((now - lastTime) / MILLISECONDS_PER_SECOND, MAX_FRAME_TIME);
    lastTime = now;
    const targetSpeed = pressedPointer !== undefined || now < boostUntil
      ? (config.pressSpeed ?? DEFAULT_PRESS_SPEED) : isHovered ? (config.hoverSpeed ?? DEFAULT_HOVER_SPEED) : 1;
    const targetDensity = pressedPointer !== undefined || now < boostUntil
      ? (config.pressDensity ?? 1) : isHovered ? (config.hoverDensity ?? 1) : 1;
    const smoothing = targetSpeed > speed ? ACCELERATION_TIME : DECELERATION_TIME;
    const smoothingFactor = 1 - Math.exp(-elapsed / smoothing);
    speed += (targetSpeed - speed) * smoothingFactor;
    if (Math.abs(targetSpeed - speed) < SPEED_THRESHOLD) speed = targetSpeed;
    density += (targetDensity - density) * smoothingFactor;
    advanceDriftParticleStream(stream, elapsed, speed, config, density);
    draw();
    frameId = requestAnimationFrame(tick);
  }

  function resume() {
    if (isDestroyed || isStatic || document.hidden || frameId !== undefined) return;
    lastTime = undefined;
    frameId = requestAnimationFrame(tick);
  }

  function reset() {
    isHovered = false;
    pressedPointer = undefined;
    boostUntil = 0;
    speed = 1;
    density = 1;
    if (frameId !== undefined) cancelAnimationFrame(frameId);
    frameId = undefined;
  }

  function handleVisibilityChange() {
    if (document.hidden) reset();
    else resume();
  }

  function handlePointerEnter(event: PointerEvent) {
    if (event.pointerType !== 'touch') isHovered = true;
  }

  function handlePointerLeave() {
    isHovered = false;
  }

  function handlePointerDown(event: PointerEvent) {
    if (event.button !== 0 || event.isPrimary === false) return;
    pressedPointer = event.pointerId;
    boostUntil = performance.now() + PRESS_BOOST_DURATION;
    if (config.shouldScatter) {
      for (let index = 0; index < BURST_COUNT; index++) {
        let particle = stream.particles.find((item) => item.isWaiting);
        if (!particle) {
          if (stream.particles.length >= stream.baseCount * MAX_DENSITY) break;
          particle = createDriftParticle(0);
          stream.particles.push(particle);
        }
        Object.assign(particle, createDriftParticle(0), { scatter: createScatterParticle(true) });
      }
    }
  }

  function handlePointerUp(event: PointerEvent) {
    if (event.pointerId === pressedPointer) pressedPointer = undefined;
  }

  function handlePointerMove(event: PointerEvent) {
    if (!(event.buttons & 1)) handlePointerUp(event);
  }

  draw();
  if (isStatic) return () => context.clearRect(0, 0, canvas.width, canvas.height);

  target?.addEventListener('pointerenter', handlePointerEnter);
  target?.addEventListener('pointerleave', handlePointerLeave);
  target?.addEventListener('pointerdown', handlePointerDown);
  target?.addEventListener('pointermove', handlePointerMove);
  target?.addEventListener('lostpointercapture', handlePointerUp);
  window.addEventListener('pointerup', handlePointerUp);
  window.addEventListener('pointercancel', handlePointerUp);
  window.addEventListener('blur', reset);
  window.addEventListener('focus', resume);
  document.addEventListener('visibilitychange', handleVisibilityChange);
  resume();

  return () => {
    isDestroyed = true;
    reset();
    target?.removeEventListener('pointerenter', handlePointerEnter);
    target?.removeEventListener('pointerleave', handlePointerLeave);
    target?.removeEventListener('pointerdown', handlePointerDown);
    target?.removeEventListener('pointermove', handlePointerMove);
    target?.removeEventListener('lostpointercapture', handlePointerUp);
    window.removeEventListener('pointerup', handlePointerUp);
    window.removeEventListener('pointercancel', handlePointerUp);
    window.removeEventListener('blur', reset);
    window.removeEventListener('focus', resume);
    document.removeEventListener('visibilitychange', handleVisibilityChange);
    context.clearRect(0, 0, canvas.width, canvas.height);
  };
}

export function createDriftParticleStream(
  count: number, duration = DEFAULT_DURATION, shouldScatter = false,
): DriftParticleStream {
  return {
    baseCount: count,
    particles: Array.from({ length: count }, (_, index) => {
      const particle = createDriftParticle(index * duration / count, duration);
      if (shouldScatter) {
        particle.scatter = createScatterParticle();
        particle.fadeInAge = Math.min(particle.progress * duration, SCATTER_FADE_IN_TIME);
        particle.fadeOutAge = particle.progress > FADE_OUT_START
          ? (particle.progress - FADE_OUT_START) / FADE_OUT_FRACTION : undefined;
        particle.opacity = particle.fadeOutAge === undefined
          ? ease(particle.fadeInAge / SCATTER_FADE_IN_TIME) : 1 - ease(particle.fadeOutAge);
      }
      return particle;
    }),
    timeUntilNext: 0,
    nextIndex: 0,
  };
}

export function advanceDriftParticleStream(
  stream: DriftParticleStream,
  elapsed: number,
  speed: number,
  {
    duration = DEFAULT_DURATION,
    fadeInTime = duration * FADE_IN_FRACTION,
    fadeOutTime = duration * FADE_OUT_FRACTION,
    shouldScatter = false,
  }: Partial<DriftParticleConfig> = {},
  densityMultiplier = 1,
) {
  const targetCount = Math.round(stream.baseCount * Math.max(1, Math.min(MAX_DENSITY, densityMultiplier)));
  while (stream.particles.length < targetCount) {
    stream.particles.push({ ...createDriftParticle(0, duration), isWaiting: true });
  }
  stream.particles.forEach((particle) => {
    if (particle.isWaiting) return;
    const previousProgress = particle.progress;
    advanceDriftParticle(particle, elapsed, speed, particle.scatter?.duration ?? duration,
      particle.scatter ? (particle.scatter.isBurst ? BURST_FADE_IN_TIME : SCATTER_FADE_IN_TIME) : fadeInTime,
      particle.scatter ? SCATTER_FADE_OUT_TIME : fadeOutTime);
    if (particle.progress < previousProgress && particle.opacity === 0) particle.isWaiting = true;
  });

  stream.timeUntilNext -= elapsed;
  if (stream.timeUntilNext > 0) return;
  if (stream.particles.filter((particle) => !particle.isWaiting).length >= targetCount) {
    stream.timeUntilNext = 0;
    return;
  }

  // A single emitter spaces births evenly; finished stars wait invisibly instead of replaying a backlog
  const { particles } = stream;
  for (let offset = 0; offset < particles.length; offset++) {
    const index = (stream.nextIndex + offset) % particles.length;
    if (!particles[index].isWaiting) continue;
    particles[index].isWaiting = false;
    if (shouldScatter) particles[index].scatter = createScatterParticle();
    stream.nextIndex = (index + 1) % particles.length;
    const lifetime = duration * FADE_OUT_START / speed + (shouldScatter ? SCATTER_FADE_OUT_TIME : fadeOutTime);
    const interval = lifetime / targetCount;
    stream.timeUntilNext = Math.max(0, stream.timeUntilNext + interval);
    return;
  }
}

export function createDriftParticle(delay: number, duration = DEFAULT_DURATION): DriftParticleState {
  const progress = (delay / duration) % 1;
  return {
    progress,
    opacity: progress < FADE_IN_FRACTION ? ease(progress / FADE_IN_FRACTION)
      : progress > FADE_OUT_START ? 1 - ease((progress - FADE_OUT_START) / FADE_OUT_FRACTION) : 1,
    fadeInAge: Math.min(progress, FADE_IN_FRACTION) * duration,
    fadeOutAge: progress > FADE_OUT_START ? (progress - FADE_OUT_START) * duration : undefined,
    fadeOutOpacity: 1,
    fadeOutStart: FADE_OUT_START,
    fadeOutSlope: 1,
    isWaiting: false,
  };
}

// Fade durations use real time, so acceleration cannot cut a fade short or reveal the position reset
export function advanceDriftParticle(
  state: DriftParticleState,
  elapsed: number,
  speed: number,
  duration = DEFAULT_DURATION,
  fadeInTime = duration * FADE_IN_FRACTION,
  fadeOutTime = duration * FADE_OUT_FRACTION,
) {
  if (state.fadeOutAge === undefined) {
    state.progress = Math.min(1, state.progress + elapsed * speed / duration);
    state.fadeInAge += elapsed;
    state.opacity = ease(state.fadeInAge / fadeInTime);
    if (state.progress >= FADE_OUT_START) {
      state.fadeOutAge = 0;
      state.fadeOutOpacity = state.opacity;
      state.fadeOutStart = state.progress;
      state.fadeOutSlope = Math.min(MAX_FADE_OUT_SLOPE, speed * fadeOutTime / (duration * (1 - state.progress)));
    }
    return;
  }

  state.fadeOutAge += elapsed;
  const time = Math.min(1, state.fadeOutAge / fadeOutTime);
  // A monotonic curve carries the entry speed into the fade without reversing or stopping visibly
  const travel = time + (state.fadeOutSlope - 1) * time * (1 - time) ** 2;
  state.progress = state.fadeOutStart + (1 - state.fadeOutStart) * travel;
  state.opacity = state.fadeOutOpacity * (1 - ease(time));
  if (time === 1) {
    state.progress = 0;
    state.fadeInAge = 0;
    state.fadeOutAge = undefined;
  }
}

export function sampleDriftParticle(state: DriftParticleState) {
  const progress = ease(state.progress);
  return { progress, scale: MIN_SCALE + progress * SCALE_GROWTH, opacity: state.opacity };
}

function createScatterParticle(isBurst = false): ScatterParticle {
  return {
    angle: Math.random() * Math.PI * 2,
    radius: isBurst
      ? BURST_MIN_RADIUS + Math.random() * BURST_RADIUS_RANGE
      : SCATTER_MIN_RADIUS + Math.random() * SCATTER_RADIUS_RANGE,
    travel: (SCATTER_MIN_TRAVEL + Math.random() * SCATTER_TRAVEL_RANGE) * (isBurst ? 1 : SCATTER_TRAVEL_MULTIPLIER),
    opacity: SCATTER_MIN_OPACITY + Math.random() * SCATTER_OPACITY_RANGE,
    duration: isBurst ? SCATTER_MIN_DURATION : SCATTER_MIN_DURATION + Math.random() * SCATTER_DURATION_RANGE,
    isBurst,
  };
}

function ease(progress: number) {
  return (1 - Math.cos(Math.PI * Math.min(1, progress))) / 2;
}
