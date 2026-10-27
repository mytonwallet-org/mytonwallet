import { clamp, lerp } from '../math';
import { type Point, quintic, randomSequence, smooth, spring } from './surfaceMotion';

interface Dot {
  anchor: Point;
  drift: Point;
  phase: number;
  opacity: number;
  radius: number;
  layoutOffset: Point;
  density: number;
  repulsion: ReturnType<typeof createRepulsion>;
}

interface DustSample {
  x: number;
  y: number;
  diameter: number;
  opacity: number;
}

const variation = (phase: number, salt: number) => {
  const v = Math.sin(phase * 127.1 + salt) * 43758.5453;

  return v - Math.floor(v);
};

type ParticleInput = 'mouse' | 'touch';

// The text fragments fly to the dust during the transition progress up to this value. The dust alone finishes the rest.
const FRAGMENT_FLIGHT_END = 0.75;

export function createRepulsion(phase: number) {
  const reach = 0.82 + variation(phase, 1.7) * 0.36;
  const strength = 0.4 + variation(phase, 8.3) * 0.6;
  const deflection = (variation(phase, 24.9) - 0.5) * 0.65;
  const response = 0.8 + variation(phase, 63.1) * 0.4;
  const offset: Point = [0, 0];
  const velocity: Point = [0, 0];

  return {
    offset,
    get isDisplaced() { return offset.some((v) => v !== 0) || velocity.some((v) => v !== 0); },
    advance(point: Point, finger: Point | undefined, drift: Point, dt: number, input: ParticleInput = 'touch') {
      let target: Point = [0, 0];

      if (finger) {
        const dx = point[0] - finger[0];
        const dy = point[1] - finger[1];
        const distance = Math.hypot(dx, dy);
        const radius = (input === 'mouse' ? 32 : 64) * reach;

        if (distance < radius) {
          const direction = distance > 0.001 ? [dx, dy] : drift;
          const length = Math.max(0.001, Math.hypot(...direction));
          const travel = (input === 'mouse' ? 14 : 40) * strength * (1 - smooth(distance / radius));

          target = [
            ((direction[0] - direction[1] * deflection) / length) * travel,
            ((direction[1] + direction[0] * deflection) / length) * travel,
          ];
        }
      }

      spring(offset, velocity, target, (target[0] === 0 && target[1] === 0 ? 14 : 24) * response, dt);

      if (target.every((v) => v === 0) && Math.hypot(...offset) < 0.001 && Math.hypot(...velocity) < 0.005) {
        offset[0] = 0;
        offset[1] = 0;
        velocity[0] = 0;
        velocity[1] = 0;
      }
    },
  };
}

function isInCapsule(x: number, y: number, width: number, height: number) {
  const r = height / 2;
  const cx = clamp(x, r, width - r);

  return Math.hypot(x - cx, y - r) <= r;
}

export function createDust(width: number, height: number, initialTime = 0) {
  const random = randomSequence(0xca4d51de);
  const countForSize = () => clamp(Math.floor(width * height * 0.28 * 0.75), 24, 6000);
  let count = countForSize();
  let isGeometryPending = false;
  const dots: Dot[] = [];

  function append(density: number) {
    let x: number;
    let y: number;

    do {
      x = random() * width;
      y = random() * height;
    } while (!isInCapsule(x, y, width, height));

    const angle = random() * Math.PI * 2;
    const speed = 0.25 + random() * 0.75;
    const phase = random();

    dots.push({
      anchor: [x, y],
      drift: [Math.cos(angle) * speed, Math.sin(angle) * speed],
      phase,
      opacity: 0.35 + random() * 0.65,
      radius: 0.35 + random() * 0.35,
      layoutOffset: [0, 0],
      density,
      repulsion: createRepulsion(phase),
    });
  }

  while (dots.length < count) append(1);

  let time = initialTime;
  let dynamicsSteps = 0;
  const samples: DustSample[] = dots.map(() => ({
    x: 0,
    y: 0,
    diameter: 0,
    opacity: 0,
  }));

  return {
    samples,
    get dynamicsSteps() { return dynamicsSteps; },
    resize(nextWidth: number, nextHeight: number) {
      if (nextWidth === width && nextHeight === height) return;

      for (const dot of dots) {
        const x = dot.anchor[0] / width * nextWidth;
        const y = dot.anchor[1] / height * nextHeight;

        // On resize, each dot stays where it is on screen and then drifts into the new size
        dot.layoutOffset[0] += dot.anchor[0] - width / 2 - (x - nextWidth / 2);
        dot.layoutOffset[1] += dot.anchor[1] - height / 2 - (y - nextHeight / 2);
        dot.anchor = [x, y];
      }

      width = nextWidth;
      height = nextHeight;
      count = countForSize();

      while (dots.length < count) {
        append(0);
        samples.push({ x: 0, y: 0, diameter: 0, opacity: 0 });
      }

      isGeometryPending = true;
    },
    get time() {
      return time;
    },
    advance(dt: number, finger?: Point, input: ParticleInput = 'touch') {
      dt = clamp(dt, 0, 1 / 15);
      time += dt;

      if (isGeometryPending) {
        isGeometryPending = false;

        const decay = Math.exp(-12 * dt);
        const blend = 1 - Math.exp(-10 * dt);

        dots.forEach((dot, i) => {
          const target = i < count ? 1 : 0;
          dot.density += (target - dot.density) * blend;

          if (Math.abs(target - dot.density) < 0.000001) dot.density = target;

          dot.layoutOffset[0] *= decay;
          dot.layoutOffset[1] *= decay;

          if (Math.hypot(...dot.layoutOffset) < 0.000001) dot.layoutOffset = [0, 0];

          isGeometryPending ||= dot.density !== target || dot.layoutOffset.some((v) => v !== 0);
        });

        while (dots.length > count && dots.at(-1)!.density < 0.001) {
          dots.pop();
          samples.pop();
        }
      }

      dots.forEach((dot, i) => {
        const age = (time + dot.phase) % 1;
        const x = dot.anchor[0] + dot.layoutOffset[0] + dot.drift[0] * (age - 0.5) * 2 * 24;
        const y = dot.anchor[1] + dot.layoutOffset[1] + dot.drift[1] * (age - 0.5) * 2 * 24;

        if (finger || dot.repulsion.isDisplaced) {
          dot.repulsion.advance([x, y], finger, dot.drift, dt, input);
          dynamicsSteps++;
        }

        const opacity = dot.opacity * dot.density * Math.sin(Math.PI * age) ** 2;
        const sample = samples[i];
        sample.x = x + dot.repulsion.offset[0];
        sample.y = y + dot.repulsion.offset[1];
        sample.diameter = dot.radius * 2.2 * 2;
        sample.opacity = opacity > 0.005 ? (Math.min(63, Math.floor(opacity * 64)) + 1) / 64 : 0;
      });
    },
  };
}

interface Fragment {
  source: Point;
  tile: number[];
  size: Point;
  bend: Point;
  delay: number;
  rotation: number;
  scale: number;
  dot: number;
}

interface DustField {
  x: number;
  y: number;
  width: number;
  height: number;
}

// Unique for any `y` within ±32768 cells
const cellKey = (x: number, y: number) => x * 65536 + y;

function captureFragments(
  image: HTMLCanvasElement,
  width: number,
  height: number,
  samples: DustSample[],
  origin: Point,
  field: DustField,
) {
  const { x: fieldX, width: fieldWidth } = field;
  const ctx = image.getContext('2d')!;
  const rgba = ctx.getImageData(0, 0, image.width, image.height).data;
  const ratio = image.width / width;
  const step = Math.max(1, Math.ceil(Math.max(0.8, 1.6 / Math.sqrt(0.75), Math.sqrt((width * height) / 9000)) * ratio));
  const random = randomSequence(0xd1571a7e);
  const uses = new Uint16Array(samples.length);
  const fragments: Fragment[] = [];
  const grid = new Map<number, number[]>();

  samples.forEach((s, i) => {
    const key = cellKey(Math.floor(s.x / 16), Math.floor(s.y / 16));
    const cell = grid.get(key);

    if (cell) cell.push(i);
    else grid.set(key, [i]);
  });

  function score(i: number, destination: Point) {
    const dx = samples[i].x - destination[0];
    const dy = samples[i].y - destination[1];

    return Math.sqrt(dx * dx + dy * dy) + uses[i] * 12;
  }

  for (let y = 0; y < image.height; y += step) {
    for (let x = 0; x < image.width; x += step) {
      const w = Math.min(step, image.width - x);
      const h = Math.min(step, image.height - y);
      let hasInk = false;

      for (let py = y; py < y + h && !hasInk; py++) {
        for (let px = x; px < x + w; px++) {
          if (rgba[(py * image.width + px) * 4 + 3] > 8) {
            hasInk = true;
            break;
          }
        }
      }

      if (!hasInk) continue;

      const source: Point = [(x + w / 2) / ratio, (y + h / 2) / ratio];
      let rx: number;
      let ry: number;

      do {
        rx = fieldX + random() * fieldWidth;
        ry = random() * field.height + field.y;
      } while (!isInCapsule(rx - fieldX, ry - field.y, fieldWidth, field.height));

      let lx = clamp(source[0], fieldX, fieldX + fieldWidth);
      let ly = clamp(source[1], field.y, field.y + field.height);

      if (!isInCapsule(lx - fieldX, ly - field.y, fieldWidth, field.height)) {
        const r = field.height / 2;
        const cx = clamp(lx, fieldX + r, fieldX + fieldWidth - r);
        const dx = lx - cx;
        const dy = ly - field.y - r;
        const s = (r - 0.01) / Math.max(r, Math.hypot(dx, dy));
        lx = cx + dx * s;
        ly = field.y + r + dy * s;
      }

      const destination: Point = [lx + (rx - lx) * 0.2, ly + (ry - ly) * 0.2];
      const dx = source[0] - origin[0];
      const dy = source[1] - origin[1];
      const distance = Math.max(1, Math.hypot(dx, dy));
      const travel = 20 * random();
      const delay = Math.min(1, distance / Math.hypot(width, height)) * 0.2;
      const cellX = Math.floor(destination[0] / 16);
      const cellY = Math.floor(destination[1] / 16);
      let dot = -1;
      let best = Infinity;

      for (let gy = -1; gy <= 1; gy++) {
        for (let gx = -1; gx <= 1; gx++) {
          for (const i of grid.get(cellKey(cellX + gx, cellY + gy)) ?? []) {
            const v = score(i, destination);

            if (v < best) {
              best = v;
              dot = i;
            }
          }
        }
      }

      if (dot < 0) {
        for (let i = 0; i < samples.length; i++) {
          const v = score(i, destination);

          if (v < best) {
            best = v;
            dot = i;
          }
        }
      }

      if (dot >= 0) uses[dot]++;

      const bend: Point = [(dx / distance) * travel, (dy / distance) * travel];
      const scale = 0.6 + random() * 0.8;
      const rotation = ((random() * 2 - 1) * 40 * Math.PI) / 180;

      fragments.push({
        source,
        tile: [x, y, w, h],
        size: [w / ratio, h / ratio],
        bend,
        delay,
        rotation,
        scale,
        dot,
      });
    }
  }

  return fragments;
}

export function sourceInkBounds(image: HTMLCanvasElement, width: number) {
  const rgba = image.getContext('2d')!.getImageData(0, 0, image.width, image.height).data;
  let left = image.width;
  let right = -1;

  for (let y = 0; y < image.height; y++) {
    for (let x = 0; x < image.width; x++) {
      if (rgba[(y * image.width + x) * 4 + 3] > 8) {
        left = Math.min(left, x);
        right = Math.max(right, x);
      }
    }
  }

  return right < left ? undefined : { x: left * width / image.width, width: (right + 1 - left) * width / image.width };
}

export function transitionFootprint(source: { x: number; width: number } | undefined,
  x: number, width: number, progress: number) {
  const t = quintic(progress / FRAGMENT_FLIGHT_END);

  return !source || t === 1 ? { x, width }
    : { x: lerp(source.x, x, t), width: lerp(source.width, width, t) };
}

export function createPrivacyField(
  canvas: HTMLCanvasElement,
  target: HTMLElement,
  snapshot: () => HTMLCanvasElement,
  width: number,
  height: number,
  palette: [string, string],
  field: DustField,
  initialTime = 0,
  retainedDust?: ReturnType<typeof createDust>,
) {
  const { x: fieldX, width: fieldWidth } = field;
  const pad = Math.max(90, Math.ceil((fieldWidth - width) / 2) + 24);
  const ctx = canvas.getContext('2d')!;
  const dust = retainedDust ?? createDust(fieldWidth, field.height, initialTime);
  dust.resize(fieldWidth, field.height);

  function advanceDust(dt: number, finger?: Point, input: ParticleInput = 'touch') {
    dust.advance(dt, finger ? [finger[0] - fieldX, finger[1] - field.y] : undefined, input);

    const footprint = transitionFootprint(ink, fieldX, fieldWidth, progress);

    for (const sample of dust.samples) {
      sample.x = footprint.x + sample.x / fieldWidth * footprint.width;
      sample.y += field.y;
    }
  }

  // The overlay is redrawn every frame while hidden, and a density above 2x costs GPU time with no visible difference
  const scale = clamp(Math.round(devicePixelRatio || 1), 1, 2);
  canvas.width = Math.round((width + pad * 2) * scale);
  canvas.height = Math.round((height + pad * 2) * scale);
  canvas.style.width = `${width + pad * 2}px`;
  canvas.style.height = `${height + pad * 2}px`;
  canvas.style.left = `${-pad}px`;
  canvas.style.top = `${-pad}px`;

  const centerX = -40 + (width + 80) * 0.3;
  const gradient = ctx.createRadialGradient(centerX, height * 0.5, 0, centerX, height * 0.5, (width + 80) * 0.6);
  gradient.addColorStop(0, palette[0]);
  gradient.addColorStop(1, palette[1]);

  // The previous field may have hidden the text mid-transition, so a new field starts with it visible
  target.style.visibility = 'visible';

  function clearOverlay() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.globalAlpha = 1;
  }

  let progress = 0;
  let isConcealed = false;
  let atlas: HTMLCanvasElement | undefined;
  let fragments: Fragment[] = [];
  let isDirty = true;
  let ink: ReturnType<typeof sourceInkBounds>;
  let previous: DustSample[] = [];
  let bridges: Point[] = [];

  function discard() {
    atlas = undefined;
    ink = undefined;
    fragments = [];
    previous = [];
    bridges = [];
  }

  function toggle(isHidden: boolean, origin: Point, isInstant = false) {
    if (isHidden === isConcealed) return;

    isDirty = true;
    isConcealed = isHidden;

    if (isInstant) {
      progress = isHidden ? 1 : 0;
      discard();
      clearOverlay();
      target.style.visibility = isHidden ? 'hidden' : 'visible';

      // A card off screen gets no animation frames, so its still frame is drawn right away,
      // before scrolling can bring the card into view
      advance(0, undefined, true);
      return;
    }

    // A reveal skips the part of the progress where only the dust moves, so the fragments start flying back at once
    if (!isHidden) progress = Math.min(progress, FRAGMENT_FLIGHT_END);

    target.style.visibility = 'hidden';

    if (!atlas) {
      try {
        atlas = snapshot();
      } catch (err) {
        // Without a snapshot there is nothing to animate, so the field goes to the end state at once: hiding keeps
        // the amount hidden, and a reveal shows it
        advance(0, undefined, true);
        throw err;
      }

      // Each tile is paired with a dust dot and flies to it while the dot keeps drifting. The tiles are paired
      // with the dots spread over the whole field, where the flight ends. The second `advanceDust` then gathers
      // the dots into the text's ink bounds from `ink`, where the transition starts.
      advanceDust(0);
      fragments = captureFragments(atlas, width, height, dust.samples, origin, field);
      ink = sourceInkBounds(atlas, width);
      advanceDust(0);
      previous = dust.samples.map((v) => ({ ...v }));
      bridges = dust.samples.map(() => [0, 0]);
    }

    // The text is hidden in this frame, so the overlay shows its copy in the same frame
    advance(0);
  }

  function advance(dt: number, finger?: Point, isInstant = false, input: ParticleInput = 'touch') {
    if (!isConcealed && !atlas && progress === 0 && !isDirty) return;

    if (isInstant && !atlas && !isDirty && progress === (isConcealed ? 1 : 0)) return;

    if (isInstant) {
      progress = isConcealed ? 1 : 0;
      discard();
      target.style.visibility = isConcealed ? 'hidden' : 'visible';
    }

    // Hiding runs the whole progress in 0.7 s, and a reveal runs back from `FRAGMENT_FLIGHT_END` in 0.6 s
    if (atlas) {
      progress = clamp(progress + (dt / (isConcealed ? 0.7 : 0.6)) * (isConcealed ? 1 : -FRAGMENT_FLIGHT_END), 0, 1);
    }

    if (isConcealed || atlas) advanceDust(isInstant ? 0 : dt, finger, input);

    ctx.setTransform(scale, 0, 0, scale, pad * scale, pad * scale);
    ctx.clearRect(-pad, -pad, width + pad * 2, height + pad * 2);

    const blend = quintic((progress - 0.1) / 0.65);

    if (atlas && progress < FRAGMENT_FLIGHT_END) {
      dust.samples.forEach((sample, i) => {
        const old = previous[i];
        const bridge = bridges[i];
        const dx = old.x - sample.x;
        const dy = old.y - sample.y;

        if (Math.hypot(dx, dy) > 8 && Math.min(old.opacity, sample.opacity) <= 1 / 64) {
          bridge[0] += dx;
          bridge[1] += dy;
        }

        bridge[0] *= Math.exp(-30 * clamp(dt, 0, 0.1));
        bridge[1] *= Math.exp(-30 * clamp(dt, 0, 0.1));
        previous[i] = { ...sample };
      });

      for (const f of fragments) {
        const s = dust.samples[f.dot];
        if (!s) continue;

        const p = quintic((progress / FRAGMENT_FLIGHT_END - f.delay) / 0.78);
        const bridge = bridges[f.dot];
        const x = lerp(f.source[0], s.x + bridge[0], p) + f.bend[0] * Math.sin(p * Math.PI);
        const y = lerp(f.source[1], s.y + bridge[1], p) + f.bend[1] * Math.sin(p * Math.PI);
        const w = lerp(lerp(f.size[0], 2.2 * 0.7 * f.scale, p), s.diameter, blend);
        const h = lerp(lerp(f.size[1], 2.2 * 0.7 * f.scale, p), s.diameter, blend);
        const a = Math.sin(p * Math.PI) * f.rotation;
        ctx.globalAlpha = (1 - blend) * lerp(1, s.opacity, blend);

        ctx.setTransform(
          scale * Math.cos(a),
          scale * Math.sin(a),
          -scale * Math.sin(a),
          scale * Math.cos(a),
          (pad + x) * scale,
          (pad + y) * scale,
        );

        ctx.drawImage(atlas, f.tile[0], f.tile[1], f.tile[2], f.tile[3], -w / 2, -h / 2, w, h);
      }
    }

    const dustOpacity = atlas ? blend : 1;

    if (progress > 0 && dustOpacity > 0) {
      // Dots are grouped into 64 opacity levels and filled as one path per level, so overlaps don't get brighter
      const paths = Array.from({ length: 64 }, () => new Path2D());

      for (const s of dust.samples) {
        if (!s.opacity) continue;

        const p = paths[Math.round(s.opacity * 64) - 1];
        p.moveTo(s.x + s.diameter / 2, s.y);
        p.arc(s.x, s.y, s.diameter / 2, 0, Math.PI * 2);
      }

      ctx.setTransform(scale, 0, 0, scale, pad * scale, pad * scale);
      ctx.fillStyle = gradient;

      paths.forEach((p, i) => {
        ctx.globalAlpha = dustOpacity * (i + 1) / 64;
        ctx.fill(p);
      });
    }

    ctx.globalAlpha = 1;
    isDirty = false;

    if (atlas && ((isConcealed && progress === 1) || (!isConcealed && progress === 0))) {
      discard();

      // At the end of the reveal the overlay still shows a copy of the text. It is cleared before the real text
      // appears, since later idle frames don't redraw the overlay.
      if (!isConcealed) clearOverlay();

      target.style.visibility = isConcealed ? 'hidden' : 'visible';
    }
  }

  return {
    toggle,
    advance,
    dust,
    get time() {
      return dust.time;
    },
    get isConcealed() {
      return isConcealed;
    },
    get progress() {
      return progress;
    },
    get isTransitioning() {
      return Boolean(atlas);
    },
  };
}
