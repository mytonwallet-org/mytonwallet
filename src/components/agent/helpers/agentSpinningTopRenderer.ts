import {
  BOX_HALF_EXTENT, buildAgentSpinningTopMesh, FLOATS_PER_VERTEX, RESTING_OFFSET_X, RESTING_OFFSET_Y,
} from './agentSpinningTopGeometry';

/** What one frame of a top draws */
export interface AgentSpinningTopFrame {
  /** Model to view, column-major */
  rotation: Float32Array;
  /** The model's origin, the top's point, from the canvas's center in pixels, y up */
  originX: number;
  originY: number;
  pixelsPerUnit: number;
  /** How firmly the top is held, 0…1: held, it turns clearer and its highlights stronger */
  strength: number;
  isDark: boolean;
  /** The color behind the top, as sRGB components 0…1 */
  backdrop: readonly [number, number, number];
  /** How strongly the thin film over the coating shows, 0…1 */
  iridescence: number;
  /** The angle the body turns during an exposure, in radians, which blurs the patterns that turn with it */
  sweep: number;
  /** How strongly the rings of a fast spin show, 0…1 */
  streaks: number;
  /** A large top stands on the ground, with a shadow or a glow under it and its reflection */
  ground?: AgentSpinningTopGround;
}

interface AgentSpinningTopGround {
  /** The camera alone, without the top's lean and spin, column-major */
  camera: Float32Array;
  /** The top mirrored in the ground through its point, seen from the camera, column-major */
  reflection: Float32Array;
  /** The ground point under the rim's center, model x and z */
  bodyX: number;
  bodyZ: number;
}

/**
 * How finely the surface is drawn: a resting top is at most a few dozen pixels high, the held one three times larger,
 * with as many rings and segments as on iOS and Android
 */
type AgentSpinningTopDetail = 'resting' | 'held';

interface MeshBuffers {
  vertexArray: WebGLVertexArrayObject;
  indexCount: number;
}

interface RendererState {
  canvas: HTMLCanvasElement;
  gl: WebGL2RenderingContext;
  program: WebGLProgram;
  groundProgram: WebGLProgram;
  groundVertexArray: WebGLVertexArrayObject;
  meshes: Partial<Record<AgentSpinningTopDetail, MeshBuffers>>;
  locations: Record<
    'rotation' | 'placement' | 'size' | 'material' | 'boxCenter' | 'backdrop' | 'effects',
    WebGLUniformLocation
  >;
  groundLocations: Record<'camera' | 'placement' | 'size' | 'body' | 'shadow' | 'color', WebGLUniformLocation>;
}

const POSITION_ATTRIBUTE = 0;
const NORMAL_ATTRIBUTE = 1;
const HIGHLIGHT_BOOST = 0.25;
// The ground under a large top: on light, a contact spot under the point and a soft shadow of the body under its rim,
// as strong as these, the body's this wide in model units; on dark, where a shadow can't darken anything, a faint blue
// glow pools there instead. The reflection in the ground shows this strongly at the point.
const LIGHT_GROUND = {
  contact: 0.5, body: 0.16, radius: 0.3, isGlow: false, color: [0, 0, 0], reflection: 0.45,
} as const;
const DARK_GROUND = {
  contact: 0.35, body: 0.16, radius: 0.32, isGlow: true, color: [0.2, 0.5, 1], reflection: 0.6,
} as const;
const MESH_RESOLUTION: Record<AgentSpinningTopDetail, [profileSamples: number, segments: number]> = {
  resting: [64, 48],
  held: [160, 144],
};
// The tops use a lower frame rate while drawing takes longer than this frame budget
const SLOW_FRAME_MS = 6;
const SLOW_FRAME_SAMPLES = 12;
const SLOW_FRAME_SMOOTHING = 0.2;
// The first frames compile the shaders on the graphics processor, which takes a while once
const WARM_UP_FRAMES = 4;

let state: RendererState | undefined;
let hasFailed = false;
let frameTimeAverage: number | undefined;
let frameTimeSamples = 0;
let warmUpFramesLeft = WARM_UP_FRAMES;
let isMeshBuiltInFrame = false;
const failureListeners = new Set<NoneToVoidFunction>();

/**
 * Whether tops can draw in 3D here. Every top draws with one WebGL2 context, each into its own canvas, so that any
 * number of them stays within the browser's limit of contexts.
 */
export function getIsAgentSpinningTopRendererAvailable() {
  return Boolean(prepareRenderer());
}

/** Called once the context is lost or the device turns out unable to draw the top; tops draw the flat mark then */
export function subscribeToAgentSpinningTopFailure(listener: NoneToVoidFunction) {
  failureListeners.add(listener);
  return () => {
    failureListeners.delete(listener);
  };
}

/** Reports whether drawing the tops stays above the frame budget */
export function reportAgentSpinningTopFrameTime(milliseconds: number) {
  const isMeshBuilt = isMeshBuiltInFrame;
  isMeshBuiltInFrame = false;
  if (hasFailed || isMeshBuilt) return;
  if (warmUpFramesLeft > 0) {
    warmUpFramesLeft -= 1;
    return;
  }

  frameTimeAverage = frameTimeAverage === undefined
    ? milliseconds
    : frameTimeAverage + (milliseconds - frameTimeAverage) * SLOW_FRAME_SMOOTHING;
  frameTimeSamples += 1;
  return frameTimeSamples >= SLOW_FRAME_SAMPLES && frameTimeAverage > SLOW_FRAME_MS;
}

/**
 * Draws `frame` into `target`, a 2D canvas, sized in device pixels. What is behind the glass is taken as the flat
 * color behind the top: over that color the glass shows as iOS shows it over its captured backdrop.
 */
export function drawAgentSpinningTop(
  target: HTMLCanvasElement,
  frame: AgentSpinningTopFrame | undefined,
  detail: AgentSpinningTopDetail = 'resting',
) {
  const context = target.getContext('2d');
  const { width, height } = target;
  if (!context || !width || !height) return;

  context.clearRect(0, 0, width, height);
  const renderer = frame ? prepareRenderer() : undefined;
  const mesh = renderer && prepareMesh(renderer, detail);
  if (!frame || !renderer || !mesh || frame.pixelsPerUnit <= 0) return;

  const { canvas, gl, program, locations } = renderer;
  const { vertexArray, indexCount } = mesh;
  // The shared canvas only grows, so that tops of different sizes do not reallocate it on every frame
  if (canvas.width < width || canvas.height < height) {
    canvas.width = Math.max(canvas.width, width);
    canvas.height = Math.max(canvas.height, height);
  }

  gl.viewport(0, 0, width, height);
  gl.enable(gl.SCISSOR_TEST);
  gl.scissor(0, 0, width, height);
  gl.clearColor(0, 0, 0, 0);
  gl.depthMask(true);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

  const look = frame.isDark ? DARK_GROUND : LIGHT_GROUND;
  const placementX = width / 2 + frame.originX;
  const placementY = height / 2 + frame.originY;
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  if (frame.ground) {
    // The ground draws under everything, without depth
    const { groundProgram, groundVertexArray, groundLocations } = renderer;
    gl.useProgram(groundProgram);
    gl.uniformMatrix4fv(groundLocations.camera, false, frame.ground.camera);
    gl.uniform3f(groundLocations.placement, placementX, placementY, frame.pixelsPerUnit);
    gl.uniform2f(groundLocations.size, width, height);
    gl.uniform2f(groundLocations.body, frame.ground.bodyX, frame.ground.bodyZ);
    gl.uniform4f(groundLocations.shadow, look.contact, look.body, look.radius, look.isGlow ? 1 : 0);
    gl.uniform3f(groundLocations.color, look.color[0], look.color[1], look.color[2]);
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.CULL_FACE);
    gl.bindVertexArray(groundVertexArray);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  gl.useProgram(program);
  gl.uniform3f(locations.placement, placementX, placementY, frame.pixelsPerUnit);
  gl.uniform2f(locations.size, width, height);
  gl.uniform3f(locations.material, frame.strength, frame.isDark ? 1 : 0, HIGHLIGHT_BOOST * frame.strength);
  gl.uniform2f(locations.boxCenter, -RESTING_OFFSET_X, -RESTING_OFFSET_Y);
  gl.uniform3f(locations.backdrop, frame.backdrop[0], frame.backdrop[1], frame.backdrop[2]);
  gl.bindVertexArray(vertexArray);
  gl.enable(gl.DEPTH_TEST);
  gl.depthFunc(gl.LESS);
  gl.enable(gl.CULL_FACE);
  if (frame.ground) {
    // The mirror flips the winding, so the reflection's outside faces clockwise; it takes the farther half of the
    // depth range, so the top always draws over it
    drawShell(gl, locations, frame.ground.reflection, gl.CW, frame, look.reflection, indexCount);
  }
  drawShell(gl, locations, frame.rotation, gl.CCW, frame, 0, indexCount);
  // eslint-disable-next-line no-null/no-null
  gl.bindVertexArray(null);

  // The drawing is still in the shared canvas's buffer within this task; its rows start at the bottom
  context.drawImage(canvas, 0, canvas.height - height, width, height, 0, 0, width, height);
}

// The mesh is closed and wound counter-clockwise from outside. The hollow shell draws its back wall first, seen from
// inside, then its front wall over it; the depth test keeps the nearest of each.
function drawShell(
  gl: WebGL2RenderingContext,
  locations: RendererState['locations'],
  rotation: Float32Array,
  frontFace: number,
  frame: AgentSpinningTopFrame,
  reflectionOpacity: number,
  indexCount: number,
) {
  gl.uniformMatrix4fv(locations.rotation, false, rotation);
  gl.uniform4f(locations.effects, frame.iridescence, frame.sweep, frame.streaks, reflectionOpacity);
  gl.frontFace(frontFace);
  for (const culledFace of [gl.FRONT, gl.BACK]) {
    gl.cullFace(culledFace);
    gl.drawElements(gl.TRIANGLES, indexCount, gl.UNSIGNED_INT, 0);
  }
}

/** Pixels per model unit of a top whose box is a square of `side` pixels */
export function getAgentSpinningTopUnit(side: number) {
  return side / 2 / BOX_HALF_EXTENT;
}

function prepareRenderer() {
  if (state || hasFailed) return state;
  if (typeof WebGL2RenderingContext === 'undefined') {
    hasFailed = true;
    return undefined;
  }

  const canvas = document.createElement('canvas');
  canvas.width = 1;
  canvas.height = 1;
  const gl = canvas.getContext('webgl2', {
    alpha: true,
    antialias: true,
    depth: true,
    premultipliedAlpha: true,
    preserveDrawingBuffer: false,
    powerPreference: 'low-power',
    // Without a usable GPU, the browser renders WebGL on the CPU, which the frame timing does not see
    failIfMajorPerformanceCaveat: true,
  });
  const prepared = gl ? prepareResources(canvas, gl) : undefined;
  if (!prepared) {
    fail();
    return undefined;
  }

  canvas.addEventListener('webglcontextlost', fail);
  state = prepared;
  return state;
}

function fail() {
  if (hasFailed) return;

  hasFailed = true;
  state = undefined;
  failureListeners.forEach((listener) => listener());
}

function prepareResources(canvas: HTMLCanvasElement, gl: WebGL2RenderingContext): RendererState | undefined {
  const program = linkProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER, (linked) => {
    gl.bindAttribLocation(linked, POSITION_ATTRIBUTE, 'aPosition');
    gl.bindAttribLocation(linked, NORMAL_ATTRIBUTE, 'aNormal');
  });
  const groundProgram = linkProgram(gl, GROUND_VERTEX_SHADER, GROUND_FRAGMENT_SHADER);
  // The ground's corners come from the vertex index, with no attributes
  const groundVertexArray = gl.createVertexArray();
  if (!program || !groundProgram || !groundVertexArray) return undefined;

  const locations = getLocations(gl, program, {
    rotation: 'uRotation',
    placement: 'uPlacement',
    size: 'uSize',
    material: 'uMaterial',
    boxCenter: 'uBoxCenter',
    backdrop: 'uBackdrop',
    effects: 'uEffects',
  });
  const groundLocations = getLocations(gl, groundProgram, {
    camera: 'uCamera',
    placement: 'uPlacement',
    size: 'uSize',
    body: 'uBody',
    shadow: 'uShadow',
    color: 'uColor',
  });
  if (!locations || !groundLocations) return undefined;

  const renderer: RendererState = {
    canvas,
    gl,
    program,
    groundProgram,
    groundVertexArray,
    meshes: {},
    locations,
    groundLocations,
  };

  return prepareMesh(renderer, 'resting') ? renderer : undefined;
}

function linkProgram(
  gl: WebGL2RenderingContext,
  vertexSource: string,
  fragmentSource: string,
  bindAttributes?: (program: WebGLProgram) => void,
) {
  const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
  const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
  const program = gl.createProgram();
  if (!vertexShader || !fragmentShader || !program) return undefined;

  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  bindAttributes?.(program);
  gl.linkProgram(program);
  gl.deleteShader(vertexShader);
  gl.deleteShader(fragmentShader);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return undefined;
  }

  return program;
}

// Every uniform must be there; a driver that drops one cannot draw the top
function getLocations<K extends string>(gl: WebGL2RenderingContext, program: WebGLProgram, names: Record<K, string>) {
  const locations = {} as Record<K, WebGLUniformLocation>;
  for (const key of Object.keys(names) as K[]) {
    const location = gl.getUniformLocation(program, names[key]);
    if (!location) return undefined;
    locations[key] = location;
  }

  return locations;
}

// The held top's finer surface is built the first time a top is held
function prepareMesh(renderer: RendererState, detail: AgentSpinningTopDetail) {
  const cached = renderer.meshes[detail];
  if (cached) return cached;

  const { gl } = renderer;
  isMeshBuiltInFrame = true;
  const mesh = buildAgentSpinningTopMesh(...MESH_RESOLUTION[detail]);
  const vertexArray = gl.createVertexArray();
  const vertexBuffer = gl.createBuffer();
  const indexBuffer = gl.createBuffer();
  if (!vertexArray || !vertexBuffer || !indexBuffer) {
    fail();
    return undefined;
  }

  gl.bindVertexArray(vertexArray);
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, mesh.vertices, gl.STATIC_DRAW);
  const stride = FLOATS_PER_VERTEX * Float32Array.BYTES_PER_ELEMENT;
  gl.enableVertexAttribArray(POSITION_ATTRIBUTE);
  gl.vertexAttribPointer(POSITION_ATTRIBUTE, 3, gl.FLOAT, false, stride, 0);
  gl.enableVertexAttribArray(NORMAL_ATTRIBUTE);
  gl.vertexAttribPointer(NORMAL_ATTRIBUTE, 3, gl.FLOAT, false, stride, 3 * Float32Array.BYTES_PER_ELEMENT);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, mesh.indices, gl.STATIC_DRAW);
  // eslint-disable-next-line no-null/no-null
  gl.bindVertexArray(null);
  if (gl.getError() !== gl.NO_ERROR) {
    fail();
    return undefined;
  }

  const buffers = { vertexArray, indexCount: mesh.indices.length };
  renderer.meshes[detail] = buffers;
  return buffers;
}

function compileShader(gl: WebGL2RenderingContext, type: number, source: string) {
  const shader = gl.createShader(type);
  if (!shader) return undefined;

  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return undefined;
  }

  return shader;
}

const VERTEX_SHADER = `#version 300 es
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
uniform mat4 uRotation;
// xy: the model's origin in pixels, y up; z: pixels per model unit
uniform vec3 uPlacement;
uniform vec2 uSize;
// w: the reflection's opacity, while the reflection is drawn
uniform vec4 uEffects;
out vec3 vViewPosition;
out vec3 vModelPosition;
out vec3 vModelNormal;

void main() {
    vec3 viewPosition = (uRotation * vec4(aPosition, 1.0)).xyz;
    vec2 pixel = uPlacement.xy + viewPosition.xy * uPlacement.z;
    // The top takes the nearer half of the depth range and its reflection the farther, so the top always draws over
    // its reflection, each hiding its own far side
    float depth = -viewPosition.z * 0.5;
    gl_Position = vec4(pixel / uSize * 2.0 - 1.0, uEffects.w > 0.0 ? 0.5 + 0.5 * depth : 0.5 * depth - 0.5, 1.0);
    vViewPosition = viewPosition;
    vModelPosition = aPosition;
    vModelNormal = aNormal;
}
`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
uniform mat4 uRotation;
// x: hold strength from 0 to 1; y: dark appearance; z: highlight boost
uniform vec3 uMaterial;
// The box's center relative to the model's origin, in view units
uniform vec2 uBoxCenter;
// The color behind the top
uniform vec3 uBackdrop;
// x: the thin film, 0…1; y: the angle the body turns during an exposure, radians; z: the rings of a fast spin, 0…1;
// w: the reflection's opacity, while the reflection is drawn
uniform vec4 uEffects;
in vec3 vViewPosition;
in vec3 vModelPosition;
in vec3 vModelNormal;
out vec4 fragColor;

vec3 computeGradient(float t) {
    vec3 c0 = vec3(0.0, 0.533, 1.0);
    vec3 c1 = vec3(0.0, 0.745, 1.0);
    vec3 c2 = vec3(0.714, 0.337, 1.0);
    return t < 0.476 ? mix(c0, c1, t / 0.476) : mix(c1, c2, (t - 0.476) / 0.524);
}

// The thin film's colors, cyclic in t: cyan, blue, violet and a short touch of pink, each blended into the next
vec3 computeFilm(float t) {
    vec3 cyan = vec3(0.0, 0.86, 1.0);
    vec3 blue = vec3(0.10, 0.45, 1.0);
    vec3 violet = vec3(0.58, 0.36, 1.0);
    vec3 pink = vec3(0.98, 0.50, 0.92);
    t = fract(t);
    if (t < 0.30) return mix(cyan, blue, smoothstep(0.0, 0.30, t));
    if (t < 0.60) return mix(blue, violet, smoothstep(0.30, 0.60, t));
    if (t < 0.75) return mix(violet, pink, smoothstep(0.60, 0.75, t));
    return mix(pink, cyan, smoothstep(0.75, 1.0, t));
}

// How much of its contrast a pattern of k cycles per turn keeps, averaged over a sweep of delta radians as the body
// turns during an exposure: 1 when nothing blurs
float computeSweepKept(float k, float delta) {
    float x = 0.5 * k * delta;
    return x < 1e-4 ? 1.0 : sin(x) / x;
}

// The reflection in the ground fades with height, strongest at the point and gone by the rim; the top itself is whole
vec4 fadeReflection(vec4 color) {
    return uEffects.w > 0.0 ? color * uEffects.w * exp(-5.0 * max(vModelPosition.y, 0.0)) : color;
}

// A broad soft window above and a cool fill below, as a matte surface blurs them
vec3 computeStudio(vec3 d) {
    float window = smoothstep(0.2, 0.95, d.y) * (0.55 + 0.45 * smoothstep(-0.7, 0.5, -d.x));
    float fill = smoothstep(-0.1, -0.9, d.y) * 0.2;
    return vec3(1.0) * window + vec3(0.55, 0.75, 1.0) * fill;
}

// A hollow top of frosted glass with a colored coating sprayed on: thin where the shell faces the viewer, so what is
// behind shows through tinted, dense where the shell turns away, and soft, matte highlights. The back wall draws
// first, the front over it.
void main() {
    float strength = clamp(uMaterial.x, 0.0, 1.0);
    bool isDark = uMaterial.y > 0.5;

    // A smooth shell without facets. Soft twisted bands in the coating turn with the body and show the spin; they
    // fade out toward the thin stem and the point, where they would flicker.
    vec3 modelNormal = normalize(vModelNormal);
    float radial = length(vModelPosition.xz);
    float azimuth = atan(vModelPosition.z, vModelPosition.x);
    float swirl = sin(2.0 * azimuth + vModelPosition.y * 4.0) * smoothstep(0.08, 0.3, radial)
        * computeSweepKept(2.0, uEffects.y);

    vec3 outward = normalize((uRotation * vec4(modelNormal, 0.0)).xyz);
    // The side of the shell that faces the viewer: the outside of the front wall, the inside of the back wall
    vec3 n = gl_FrontFacing ? outward : -outward;
    vec3 v = vec3(0.0, 0.0, 1.0);
    float grazing = 1.0 - clamp(n.z, 0.0, 1.0);
    float fresnel = pow(grazing, 2.2);

    vec2 fromCenter = vViewPosition.xy - uBoxCenter;
    float t = clamp(dot(fromCenter, vec2(0.96, -0.27)) * 0.55 + 0.5 + 0.07 * swirl, 0.0, 1.0);
    vec3 base = computeGradient(t);
    // The coating is a little uneven, as sprayed on
    float coatDensity = 1.0 + 0.12 * swirl;

    // A thin film over the coating, shifting through its colors as the top turns and toward the silhouette
    float iridescence = clamp(uEffects.x, 0.0, 1.0);
    float thickness = 0.45
        + 0.22 * sin(azimuth + 3.0 * vModelPosition.y) * computeSweepKept(1.0, uEffects.y)
        + 0.12 * sin(3.0 * azimuth - 5.0 * vModelPosition.y) * computeSweepKept(3.0, uEffects.y);
    vec3 film = computeFilm(thickness + 0.55 * grazing);

    vec3 light = normalize(vec3(-0.45, 0.75, 0.5));
    float diffuse = 0.7 + 0.3 * clamp(dot(n, light), 0.0, 1.0);
    float halfway = clamp(dot(n, normalize(light + v)), 0.0, 1.0);
    // Frosted glass scatters its highlights: wide and soft, no sharp glint
    float sheen = (pow(halfway, 10.0) * 0.16 + pow(halfway, 36.0) * 0.12) * (1.0 + uMaterial.z);

    if (!gl_FrontFacing) {
        // The back wall, seen through the hollow: what is behind, tinted by the coating it passes, which gathers
        // where the wall turns away, under a milky veil
        float wall = mix(isDark ? 0.2 : 0.16, 0.55, fresnel) * coatDensity * mix(1.0, 0.7, strength);
        vec3 wallColor = mix(base * (isDark ? 0.78 : 0.9), film, 0.35 * iridescence * fresnel);
        vec3 transmittance = mix(vec3(1.0), base, 0.55);
        float veil = isDark ? 0.05 : 0.1;
        vec3 transmitted = mix(uBackdrop * transmittance, vec3(isDark ? 0.75 : 1.0), veil);
        vec3 seen = mix(transmitted, wallColor, wall);
        // The share of what is behind that still shows: over the backdrop's color the wall shows exactly what is seen
        float clearest = min(transmittance.r, min(transmittance.g, transmittance.b));
        float clearness = (1.0 - wall) * (1.0 - veil) * clearest;
        float opacity = 1.0 - clearness;
        fragColor = fadeReflection(vec4(clamp(seen - uBackdrop * clearness, 0.0, opacity), opacity));
        return;
    }

    // The front wall: a thin colored coat over the hollow, denser toward the silhouette, with the matte sheen and a
    // soft rim where the frosted surface scatters the light around it
    vec3 coat = mix(base * diffuse, film, iridescence * (0.18 + 0.5 * fresnel));
    coat += computeStudio(reflect(-v, n)) * (0.06 + 0.22 * fresnel);
    coat = mix(coat, vec3(1.0), fresnel * (isDark ? 0.18 : 0.24));
    vec3 sheenColor = mix(vec3(1.0), film, 0.7 * iridescence);
    // A fast spin smears the surface into fine rings around the body
    float rings = pow(0.5 + 0.5 * sin(46.0 * vModelPosition.y + 1.7 * sin(13.0 * vModelPosition.y)), 6.0)
        * smoothstep(0.08, 0.3, radial) * clamp(uEffects.z, 0.0, 1.0);
    coat = clamp(coat + sheenColor * sheen * (1.0 + 0.8 * iridescence) + 0.35 * rings, 0.0, 1.0);
    float facing = mix(isDark ? 0.34 : 0.3, 0.16, strength);
    float coverage = mix(facing, 0.82, smoothstep(0.05, 0.95, grazing));
    float opacity = clamp(coverage * coatDensity + sheen + 0.12 * rings, 0.0, 1.0);
    vec4 color = vec4(coat * opacity, opacity);
    // A rim light along the silhouette in the film's colors: added light on dark, a tint on light, where added light
    // wouldn't show
    float rim = pow(grazing, 3.5) * iridescence;
    if (isDark) {
        color.rgb += film * rim * 0.9;
    } else {
        color.rgb = mix(color.rgb, film * color.a, clamp(0.8 * rim, 0.0, 1.0));
    }
    fragColor = fadeReflection(color);
}
`;

// The ground under a large top, in the plane through its point, seen from the camera alone
const GROUND_VERTEX_SHADER = `#version 300 es
uniform mat4 uCamera;
// xy: the top's point in pixels, y up; z: pixels per model unit
uniform vec3 uPlacement;
uniform vec2 uSize;
out vec2 vGround;

void main() {
    vec2 ground = vec2(gl_VertexID % 2 == 0 ? -1.6 : 1.6, gl_VertexID < 2 ? -1.6 : 1.6);
    vec3 viewPosition = (uCamera * vec4(ground.x, 0.0, ground.y, 1.0)).xyz;
    vec2 pixel = uPlacement.xy + viewPosition.xy * uPlacement.z;
    gl_Position = vec4(pixel / uSize * 2.0 - 1.0, 0.0, 1.0);
    vGround = ground;
}
`;

// A contact spot under the point and a soft shadow of the body under its rim, which follows the lean. On dark, where a
// shadow can't darken anything, it pools faint light.
const GROUND_FRAGMENT_SHADER = `#version 300 es
precision highp float;
// The ground point under the rim's center, model x and z
uniform vec2 uBody;
// x: the contact spot's strength; y: the body's; z: the body's radius, model units; w: a glow rather than a shadow
uniform vec4 uShadow;
uniform vec3 uColor;
in vec2 vGround;
out vec4 fragColor;

void main() {
    float contact = exp(-dot(vGround, vGround) / (2.0 * 0.045 * 0.045));
    vec2 fromBody = vGround - uBody;
    float body = exp(-dot(fromBody, fromBody) / (2.0 * uShadow.z * uShadow.z));
    float amount = clamp(uShadow.x * contact + uShadow.y * body, 0.0, 1.0);
    // Premultiplied: a shadow darkens what is behind, a glow adds light to it
    fragColor = uShadow.w > 0.5 ? vec4(uColor * amount, 0.0) : vec4(uColor * amount, amount);
}
`;
