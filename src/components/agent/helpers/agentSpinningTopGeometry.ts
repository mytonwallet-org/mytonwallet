/**
 * The Agent's spinning top as a smooth surface of revolution around the y axis: a rounded point, concave flanks that
 * flare to a thin rim low on the body with a rounded edge, a long concave flare up into the stem, and a rounded cap.
 * The point sits at the origin, where the top pivots as it precesses. The same surface as on iOS and Android.
 */

/** The camera's elevation above the rim's plane, at which the top shows the mark's silhouette */
export const VIEW_PITCH = (9.2 * Math.PI) / 180;

/** The lean of the spin axis, which the mark shows leaning to the right */
export const LEAN = (11 * Math.PI) / 180;

/** Where the point sits in the square box, relative to its center, in model units, y up: the mark's point */
export const RESTING_OFFSET_X = -0.134;
export const RESTING_OFFSET_Y = -0.722;

/** Half of the box side in model units: the mark's 48 px box at 26.1 px per unit */
export const BOX_HALF_EXTENT = 0.92;

/** The extent of something along one axis of the window, in CSS pixels */
interface AgentExpansionSpan {
  start: number;
  end: number;
}

/** A top growing out of its resting place keeps this far from the window's sides, unless it rests nearer already */
const SCREEN_EDGE_INSET = 16;

/** Position and normal of each vertex, three floats each */
export const FLOATS_PER_VERTEX = 6;

/**
 * The profile in (radius, height), from the point up to the cap, through which a centripetal Catmull–Rom spline runs.
 * The rim, 0.68 across from the axis, is the widest ring.
 */
const PROFILE: readonly (readonly [number, number])[] = [
  [0.0000, 0.0000],
  [0.0356, 0.0067],
  [0.0649, 0.0318],
  [0.0822, 0.0627],
  [0.1203, 0.1331],
  [0.1756, 0.2413],
  [0.2366, 0.3151],
  [0.2874, 0.3543],
  [0.3389, 0.3844],
  [0.4176, 0.4191],
  [0.5191, 0.4496],
  [0.6140, 0.4676],
  // The rim: its lower edge, its rounded outer edge and its upper edge
  [0.6467, 0.4727],
  [0.6630, 0.4810],
  [0.6747, 0.4929],
  [0.6791, 0.5093],
  [0.6747, 0.5256],
  [0.6630, 0.5375],
  [0.6467, 0.5458],
  [0.6102, 0.5520],
  [0.5190, 0.5734],
  [0.4677, 0.5895],
  [0.3864, 0.6215],
  [0.3408, 0.6444],
  [0.3082, 0.6673],
  [0.2333, 0.7440],
  [0.1967, 0.7981],
  [0.1761, 0.8423],
  [0.1556, 0.9032],
  [0.1271, 1.0183],
  [0.1060, 1.1741],
  [0.0917, 1.3553],
  [0.0740, 1.4280],
  [0.0526, 1.4588],
  [0.0353, 1.4705],
  [0.0000, 1.4797],
];

const DENSE_PROFILE_STEPS_PER_SPAN = 96;
const TURNING_ANGLE_SHARE = 0.05;

interface AgentSpinningTopMesh {
  vertices: Float32Array;
  indices: Uint32Array;
}

interface ProfilePoint {
  x: number;
  y: number;
  tangentX: number;
  tangentY: number;
}

/** Enough rings and segments that the smooth shading shows no facets even on the held top, three times larger */
export function buildAgentSpinningTopMesh(profileSamples = 160, segments = 144): AgentSpinningTopMesh {
  const rings = sampleProfile(profileSamples);
  const vertices = new Float32Array(rings.length * segments * FLOATS_PER_VERTEX);
  let cursor = 0;
  rings.forEach((ring, index) => {
    // Outward normal of the profile, which runs upward; the poles face straight down and up
    let normalX = ring.tangentY;
    let normalY = -ring.tangentX;
    if (index === 0) {
      normalX = 0;
      normalY = -1;
    } else if (index === rings.length - 1) {
      normalX = 0;
      normalY = 1;
    }
    for (let segment = 0; segment < segments; segment++) {
      const angle = (segment / segments) * 2 * Math.PI;
      const cosine = Math.cos(angle);
      const sine = Math.sin(angle);
      vertices[cursor++] = ring.x * cosine;
      vertices[cursor++] = ring.y;
      vertices[cursor++] = ring.x * sine;
      // The profile's unit normal, turned around the axis with the segment
      vertices[cursor++] = normalX * cosine;
      vertices[cursor++] = normalY;
      vertices[cursor++] = normalX * sine;
    }
  });

  const indices = new Uint32Array((rings.length - 1) * segments * 6);
  cursor = 0;
  for (let ring = 0; ring < rings.length - 1; ring++) {
    for (let segment = 0; segment < segments; segment++) {
      const next = (segment + 1) % segments;
      const a = ring * segments + segment;
      const b = ring * segments + next;
      const c = (ring + 1) * segments + segment;
      const d = (ring + 1) * segments + next;
      // Counter-clockwise when seen from outside
      indices[cursor++] = a;
      indices[cursor++] = c;
      indices[cursor++] = b;
      indices[cursor++] = b;
      indices[cursor++] = c;
      indices[cursor++] = d;
    }
  }

  return { vertices, indices };
}

/**
 * Points along the profile, spaced by arc length plus a share of the turning angle, so the rounded point, the rim and
 * the cap get denser rings than the gently curving flanks
 */
function sampleProfile(count: number): ProfilePoint[] {
  const dense = makeDenseProfile(DENSE_PROFILE_STEPS_PER_SPAN);
  const measure = new Float64Array(dense.length);
  for (let i = 1; i < dense.length; i++) {
    const length = Math.hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y);
    const dot = dense[i].tangentX * dense[i - 1].tangentX + dense[i].tangentY * dense[i - 1].tangentY;
    const turn = Math.acos(Math.min(1, Math.max(-1, dot)));
    measure[i] = measure[i - 1] + length + TURNING_ANGLE_SHARE * turn;
  }

  const total = measure[measure.length - 1];
  const points: ProfilePoint[] = [];
  let j = 0;
  for (let k = 0; k < count; k++) {
    const target = (total * k) / (count - 1);
    while (j < dense.length - 2 && measure[j + 1] < target) j++;
    const span = Math.max(measure[j + 1] - measure[j], 1e-6);
    const f = Math.min(1, Math.max(0, (target - measure[j]) / span));
    const from = dense[j];
    const to = dense[j + 1];
    const tangentX = from.tangentX + (to.tangentX - from.tangentX) * f;
    const tangentY = from.tangentY + (to.tangentY - from.tangentY) * f;
    const tangentLength = Math.max(Math.hypot(tangentX, tangentY), 1e-6);
    points.push({
      x: from.x + (to.x - from.x) * f,
      y: from.y + (to.y - from.y) * f,
      tangentX: tangentX / tangentLength,
      tangentY: tangentY / tangentLength,
    });
  }

  return points;
}

/** The spline sampled finely, with tangents from neighbouring samples */
function makeDenseProfile(stepsPerSpan: number): ProfilePoint[] {
  const first = PROFILE[0];
  const second = PROFILE[1];
  const last = PROFILE[PROFILE.length - 1];
  const beforeLast = PROFILE[PROFILE.length - 2];
  const controls = [
    [2 * first[0] - second[0], 2 * first[1] - second[1]] as const,
    ...PROFILE,
    [2 * last[0] - beforeLast[0], 2 * last[1] - beforeLast[1]] as const,
  ];
  const points: (readonly [number, number])[] = [];
  for (let span = 1; span < controls.length - 2; span++) {
    for (let step = 0; step < stepsPerSpan; step++) {
      points.push(computeCentripetalPoint(
        controls[span - 1], controls[span], controls[span + 1], controls[span + 2], step / stepsPerSpan,
      ));
    }
  }
  points.push(last);

  return points.map((point, i) => {
    const previous = points[Math.max(0, i - 1)];
    const next = points[Math.min(points.length - 1, i + 1)];
    const dx = next[0] - previous[0];
    const dy = next[1] - previous[1];
    const length = Math.max(Math.hypot(dx, dy), 1e-6);
    return {
      x: point[0], y: point[1], tangentX: dx / length, tangentY: dy / length,
    };
  });
}

/** A point of the centripetal Catmull–Rom span from `p1` to `p2`, which neither overshoots nor loops at the rim */
function computeCentripetalPoint(
  p0: readonly [number, number],
  p1: readonly [number, number],
  p2: readonly [number, number],
  p3: readonly [number, number],
  fraction: number,
): readonly [number, number] {
  function advanceKnot(t: number, a: readonly [number, number], b: readonly [number, number]) {
    return t + Math.sqrt(Math.max(Math.hypot(b[0] - a[0], b[1] - a[1]), 1e-6));
  }
  const t0 = 0;
  const t1 = advanceKnot(t0, p0, p1);
  const t2 = advanceKnot(t1, p1, p2);
  const t3 = advanceKnot(t2, p2, p3);
  const t = t1 + (t2 - t1) * fraction;
  function interpolate(axis: 0 | 1) {
    const a1 = ((t1 - t) / (t1 - t0)) * p0[axis] + ((t - t0) / (t1 - t0)) * p1[axis];
    const a2 = ((t2 - t) / (t2 - t1)) * p1[axis] + ((t - t1) / (t2 - t1)) * p2[axis];
    const a3 = ((t3 - t) / (t3 - t2)) * p2[axis] + ((t - t2) / (t3 - t2)) * p3[axis];
    const b1 = ((t2 - t) / (t2 - t0)) * a1 + ((t - t0) / (t2 - t0)) * a2;
    const b2 = ((t3 - t) / (t3 - t1)) * a2 + ((t - t1) / (t3 - t1)) * a3;
    return ((t2 - t) / (t2 - t1)) * b1 + ((t - t1) / (t2 - t1)) * b2;
  }

  return [interpolate(0), interpolate(1)];
}

/**
 * The top turned by `yaw` about its own axis, the axis leaning by `lean` toward `leanDirection` and pivoting on the
 * point at the origin, all seen from `pitch` above, into `out` as a column-major 4 × 4 matrix. Direction 0 leans to
 * the right, as the mark does. A growing yaw and lean direction turn counter-clockwise as seen from above; the top,
 * which spins clockwise, passes both negated.
 */
export function computeAgentSpinningTopTransform(
  yaw: number,
  pitch: number,
  lean: number,
  leanDirection: number,
  out: Float32Array,
) {
  // Quaternions as (x, y, z, w): the spin about y, the tilt toward (cos ψ, 0, −sin ψ) about up × that direction,
  // and the camera's pitch about x
  const spinSin = Math.sin(yaw / 2);
  const spinCos = Math.cos(yaw / 2);
  const tiltSin = Math.sin(lean / 2);
  const tiltCos = Math.cos(lean / 2);
  const tiltX = -Math.sin(leanDirection) * tiltSin;
  const tiltZ = -Math.cos(leanDirection) * tiltSin;
  const cameraSin = Math.sin(pitch / 2);
  const cameraCos = Math.cos(pitch / 2);
  // Tilt × spin, spin being (0, `spinSin`, 0, `spinCos`)
  const tiltSpinX = tiltX * spinCos - tiltZ * spinSin;
  const tiltSpinY = tiltCos * spinSin;
  const tiltSpinZ = tiltZ * spinCos + tiltX * spinSin;
  const tiltSpinW = tiltCos * spinCos;
  // Camera × (tilt × spin), camera being (`cameraSin`, 0, 0, `cameraCos`)
  const x = cameraCos * tiltSpinX + cameraSin * tiltSpinW;
  const y = cameraCos * tiltSpinY - cameraSin * tiltSpinZ;
  const z = cameraCos * tiltSpinZ + cameraSin * tiltSpinY;
  const w = cameraCos * tiltSpinW - cameraSin * tiltSpinX;
  out[0] = 1 - 2 * (y * y + z * z);
  out[1] = 2 * (x * y + z * w);
  out[2] = 2 * (x * z - y * w);
  out[3] = 0;
  out[4] = 2 * (x * y - z * w);
  out[5] = 1 - 2 * (x * x + z * z);
  out[6] = 2 * (y * z + x * w);
  out[7] = 0;
  out[8] = 2 * (x * z + y * w);
  out[9] = 2 * (y * z - x * w);
  out[10] = 1 - 2 * (x * x + y * y);
  out[11] = 0;
  out[12] = 0;
  out[13] = 0;
  out[14] = 0;
  out[15] = 1;
}

/**
 * How far something growing out of its resting place moves along one axis of the window, away from a side it would
 * otherwise cross: toward the middle, keeping 16 px from the side, or as far from it as its resting place is already.
 * The held spinning top grows this way.
 */
export function getAgentExpansionShift(resting: AgentExpansionSpan, grown: AgentExpansionSpan, windowSide: number) {
  const startInset = Math.max(0, Math.min(SCREEN_EDGE_INSET, resting.start));
  const endInset = Math.max(0, Math.min(SCREEN_EDGE_INSET, windowSide - resting.end));
  if (grown.start < startInset) return startInset - grown.start;
  if (grown.end > windowSide - endInset) return windowSide - endInset - grown.end;
  return 0;
}
