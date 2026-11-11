import { getAgentGlowColors } from './agentGlowPalette';

// The iOS edge glow (`AgentEdgeGlow.metal`) as a WebGL fragment shader, drawn over four strips along the edges, the
// bottom one tall enough for the lights that drift behind the composer

/** The motion repeats every this many seconds: every stretch and light goes round a whole number of times in it */
const MOTION_PERIOD = 24;
/** How far in from the rounded edge the edge's light reaches, in CSS pixels */
const GLOW_DEPTH = 32;
/** How far up from the bottom the drifting lights reach, in CSS pixels */
const LIGHTS_HEIGHT = 150;
/** Pixels per CSS pixel are capped, as on iOS */
const MAX_PIXEL_RATIO = 2;
const COS_45_DEGREES = 0.7071;

/**
 * Where a point lies relative to a rounded rectangle centred at the origin: its signed distance from the edge, and
 * where along the edge the point of it nearest lies, clockwise from the middle of the top edge, with the edge's length
 * in `total`. The edge glow and the field's rim share them, as their iOS shaders do.
 */
export const ROUNDED_RECT_GLSL = `
const float HALF_PI = 1.5707963;
const float PI = 3.1415927;

float getRoundedRectDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float getBorderAlong(vec2 local, vec2 halfSize, float radius, out float total) {
  vec2 inner = max(halfSize - radius, 0.0);
  float arc = HALF_PI * radius;
  total = 4.0 * (inner.x + inner.y + arc);
  vec2 q = clamp(local, -inner, inner);
  vec2 d = local - q;
  vec2 border;
  if (length(d) > 1e-3) {
    border = q + normalize(d) * radius;
  } else if (inner.y - abs(local.y) < inner.x - abs(local.x)) {
    border = vec2(local.x, sign(local.y) * halfSize.y);
  } else {
    border = vec2(sign(local.x) * halfSize.x, local.y);
  }
  // Strictly within the straight part, so that with square corners a point of a side stays on the side
  if (abs(border.x) < inner.x) {
    // The top edge, its left half at the end of the loop, or the bottom edge
    if (border.y < 0.0) return border.x >= 0.0 ? border.x : total + border.x;
    return 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y - (border.x + inner.x);
  }
  if (abs(border.y) <= inner.y) {
    // The right edge, or the left one
    if (border.x > 0.0) return inner.x + arc + (border.y + inner.y);
    return 3.0 * inner.x + 3.0 * arc + 2.0 * inner.y + (inner.y - border.y);
  }
  // A corner: the angle clockwise from up around its centre
  vec2 centre = sign(border) * inner;
  vec2 v = border - centre;
  float angle = atan(v.x, -v.y);
  if (angle < 0.0) angle += 2.0 * PI;
  if (angle <= HALF_PI) return inner.x + radius * angle;
  if (angle <= PI) return inner.x + arc + 2.0 * inner.y + radius * (angle - HALF_PI);
  if (angle <= 1.5 * PI) return 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y + radius * (angle - PI);
  return 3.0 * inner.x + 3.0 * arc + 4.0 * inner.y + radius * (angle - 1.5 * PI);
}
`;

const VERTEX_SHADER = `
attribute vec2 a_position;
uniform vec2 u_size;

void main() {
  vec2 clip = a_position / u_size * 2.0 - 1.0;
  gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);
}
`;

const FRAGMENT_SHADER = `
precision highp float;

uniform vec2 u_size;
uniform float u_pixelRatio;
uniform float u_radius;
uniform float u_time;
uniform vec3 u_blue;
uniform vec3 u_purple;

const float PERIOD = ${MOTION_PERIOD.toFixed(1)};
const float DEPTH = ${GLOW_DEPTH.toFixed(1)};
const float LIGHTS_HEIGHT = ${LIGHTS_HEIGHT.toFixed(1)};

${ROUNDED_RECT_GLSL}

// A bright stretch of the edge that goes round loops times a period, from start of the way round, sigma pixels long on
// either side
float getStretch(float along, float total, float start, float loops, float sigma) {
  float centre = fract(start + loops * u_time / PERIOD) * total;
  float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
  return exp(-d * d / (2.0 * sigma * sigma));
}

// A soft light spreading over sigma pixels
float getLight(vec2 xy, vec2 centre, float sigma) {
  vec2 d = xy - centre;
  return exp(-dot(d, d) / (2.0 * sigma * sigma));
}

// A slow sway that repeats cycles times a period
float getSway(float cycles, float phase) {
  return sin(2.0 * PI * cycles * u_time / PERIOD + phase);
}

// iOS's agentEdgeGlowFragment: a thin, almost white core line along the rounded edge, a short bright bloom and a
// longer softer haze inward, and blue and purple stretches running along it at their own speeds, whitening at their
// brightest. The edge is brighter toward the bottom and toward both sides alike, and faint lights drift behind the
// composer.
void main() {
  vec2 xy = vec2(gl_FragCoord.x, u_size.y * u_pixelRatio - gl_FragCoord.y) / u_pixelRatio;
  vec2 size = u_size;
  vec2 halfSize = size * 0.5;
  vec2 local = xy - halfSize;
  float edgeDistance = getRoundedRectDistance(local, halfSize, u_radius);
  float inset = max(-edgeDistance, 0.0);
  float fromBottom = size.y - xy.y;
  if (inset >= DEPTH && fromBottom >= LIGHTS_HEIGHT) {
    gl_FragColor = vec4(0.0);
    return;
  }

  vec3 color = vec3(0.0);
  float alpha = 0.0;
  if (inset < DEPTH) {
    float total;
    float along = getBorderAlong(local, halfSize, u_radius, total);
    // Each stretch at its own speed, some going the other way
    float blue = getStretch(along, total, 0.0, 7.0, 72.0)
      + 0.8 * getStretch(along, total, 0.55, -4.0, 88.0)
      + 0.7 * getStretch(along, total, 0.2, 9.0, 52.0);
    float purple = 0.9 * getStretch(along, total, 0.3, 5.0, 64.0)
      + 0.8 * getStretch(along, total, 0.8, -3.0, 80.0);
    float stretches = blue + purple;

    float down = clamp(xy.y / size.y, 0.0, 1.0);
    float fromSide = min(xy.x, size.x - xy.x);
    float nearSide = exp(-max(fromSide, 0.0) / 120.0);
    float base = 0.3 + 0.45 * down * down + 0.175 * nearSide;
    float intensity = base * (0.25 + 1.5 * stretches);

    // Between the stretches the edge keeps a little of both colours
    vec3 stretchColor = (u_blue * blue + u_purple * purple + 0.06 * (u_blue + u_purple)) / (stretches + 0.12);
    float core = exp(-inset * inset / (2.0 * 0.9 * 0.9));
    float bloom = exp(-inset / 4.5);
    float haze = 0.4 * exp(-inset / 13.0);
    float fade = 1.0 - smoothstep(0.6 * DEPTH, DEPTH, inset);
    float glow = (bloom + haze) * intensity;
    float coreAlpha = clamp(core * intensity, 0.0, 1.0);
    float glowAlpha = clamp(glow * fade, 0.0, 0.9);
    // The core whitens the brighter it is, and so does the bloom at its brightest
    vec3 coreColor = mix(stretchColor, vec3(1.0), clamp(0.5 + 0.4 * intensity, 0.0, 0.92));
    vec3 glowColor = mix(stretchColor, vec3(1.0), clamp((glow - 0.9) * 0.5, 0.0, 0.5));
    color = coreColor * coreAlpha + glowColor * glowAlpha * (1.0 - coreAlpha);
    alpha = coreAlpha + glowAlpha * (1.0 - coreAlpha);
  }
  if (fromBottom < LIGHTS_HEIGHT) {
    // Large faint lights a little inside the edge, swaying under its light, each a few times a period. The two side
    // ones mirror each other in place, size and strength.
    vec2 first = vec2(
      size.x * (0.28 + 0.19 * getSway(2.0, 0.0)),
      size.y - LIGHTS_HEIGHT * (0.45 + 0.08 * getSway(4.0, 1.0))
    );
    vec2 second = vec2(
      size.x * (0.72 + 0.19 * getSway(2.0, 2.0)),
      size.y - LIGHTS_HEIGHT * (0.38 + 0.08 * getSway(6.0, 2.5))
    );
    vec2 third = vec2(
      size.x * (0.5 + 0.32 * getSway(4.0, 4.0)),
      size.y - LIGHTS_HEIGHT * (0.58 + 0.06 * getSway(2.0, 3.0))
    );
    float firstLight = getLight(xy, first, 0.52 * LIGHTS_HEIGHT);
    float secondLight = getLight(xy, second, 0.52 * LIGHTS_HEIGHT);
    float thirdLight = getLight(xy, third, 0.62 * LIGHTS_HEIGHT);
    float blueLight = 0.21 * firstLight + 0.15 * thirdLight;
    float purpleLight = 0.21 * secondLight;
    float lightsFade = 1.0 - smoothstep(0.5 * LIGHTS_HEIGHT, LIGHTS_HEIGHT, fromBottom);
    float lightsAlpha = 0.5 * clamp((blueLight + purpleLight) * lightsFade, 0.0, 0.35);
    vec3 lightsColor = (u_blue * blueLight + u_purple * purpleLight) / max(blueLight + purpleLight, 1e-4);
    color += lightsColor * lightsAlpha * (1.0 - alpha);
    alpha += lightsAlpha * (1.0 - alpha);
  }
  // Nothing shows past the rounded edge, which is smoothed over a pixel
  float edge = clamp(0.5 - edgeDistance * u_pixelRatio, 0.0, 1.0);
  gl_FragColor = vec4(color, alpha) * edge;
}
`;

interface AgentEdgeGlowRenderer {
  /** Fits the drawing to the glow's box, in CSS pixels, with the radius of its rounded corners */
  resize: (width: number, height: number, cornerRadius: number) => void;
  /** Draws the glow `time` seconds into its motion, in the Agent's colours for the theme */
  render: (time: number, isDark: boolean) => void;
  destroy: NoneToVoidFunction;
}

export function createAgentEdgeGlowRenderer(canvas: HTMLCanvasElement): AgentEdgeGlowRenderer | undefined {
  // Without a usable GPU, the browser renders WebGL on the CPU, and the CSS glow costs less
  const gl = canvas.getContext('webgl', {
    alpha: true, premultipliedAlpha: true, antialias: false, depth: false, failIfMajorPerformanceCaveat: true,
  });
  if (!gl) return undefined;

  const program = createGlowProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
  if (!program) {
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    return undefined;
  }

  const buffer = gl.createBuffer();
  const positionLocation = gl.getAttribLocation(program, 'a_position');
  const sizeLocation = gl.getUniformLocation(program, 'u_size');
  const pixelRatioLocation = gl.getUniformLocation(program, 'u_pixelRatio');
  const radiusLocation = gl.getUniformLocation(program, 'u_radius');
  const timeLocation = gl.getUniformLocation(program, 'u_time');
  const blueLocation = gl.getUniformLocation(program, 'u_blue');
  const purpleLocation = gl.getUniformLocation(program, 'u_purple');

  let width = 0;
  let height = 0;
  let radius = 0;
  let pixelRatio = 1;
  let vertexCount = 0;

  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
  gl.clearColor(0, 0, 0, 0);

  return {
    resize(nextWidth, nextHeight, cornerRadius) {
      width = nextWidth;
      height = nextHeight;
      radius = Math.min(cornerRadius, width / 2, height / 2);
      pixelRatio = Math.min(MAX_PIXEL_RATIO, window.devicePixelRatio || 1);
      canvas.width = Math.max(1, Math.ceil(width * pixelRatio));
      canvas.height = Math.max(1, Math.ceil(height * pixelRatio));
      gl.viewport(0, 0, canvas.width, canvas.height);

      const vertices = buildStripVertices(width, height, radius);
      vertexCount = vertices.length / 2;
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
    },

    render(time, isDark) {
      gl.clear(gl.COLOR_BUFFER_BIT);
      if (!vertexCount) return;
      const { blue, violet } = getAgentGlowColors(isDark);
      gl.uniform2f(sizeLocation, width, height);
      gl.uniform1f(pixelRatioLocation, pixelRatio);
      gl.uniform1f(radiusLocation, radius);
      // The time wraps with the motion, which keeps it precise however long the glow runs
      gl.uniform1f(timeLocation, time % MOTION_PERIOD);
      gl.uniform3f(blueLocation, blue[0] / 255, blue[1] / 255, blue[2] / 255);
      gl.uniform3f(purpleLocation, violet[0] / 255, violet[1] / 255, violet[2] / 255);
      gl.drawArrays(gl.TRIANGLES, 0, vertexCount);
    },

    // The context is released at once rather than when the canvas is collected, since the browser keeps only a few
    // live contexts and takes the oldest, such as the spinning top's, when a new one exceeds them
    destroy() {
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    },
  };
}

// The four strips the glow lies in: deep enough that they cover the band where it curves in along a rounded corner,
// whose inner edge is a quarter circle reaching furthest on the diagonal, and the bottom one as tall as the lights
// reach
function buildStripVertices(width: number, height: number, radius: number) {
  const innerRadius = Math.max(0, radius - GLOW_DEPTH);
  const depth = Math.ceil(Math.max(GLOW_DEPTH, radius - innerRadius * COS_45_DEGREES)) + 2;
  const bottomDepth = Math.min(Math.max(depth, LIGHTS_HEIGHT), height / 2);
  const sideHeight = Math.max(0, height - depth - bottomDepth);
  const rects = [
    [0, 0, width, Math.min(depth, height)],
    [Math.max(0, width - depth), depth, Math.min(depth, width), sideHeight],
    [0, Math.max(0, height - bottomDepth), width, Math.min(bottomDepth, height)],
    [0, depth, Math.min(depth, width), sideHeight],
  ].filter(([, , rectWidth, rectHeight]) => rectWidth > 0 && rectHeight > 0);

  return new Float32Array(rects.flatMap(([x, y, rectWidth, rectHeight]) => [
    x, y, x + rectWidth, y, x, y + rectHeight,
    x, y + rectHeight, x + rectWidth, y, x + rectWidth, y + rectHeight,
  ]));
}

export function createGlowProgram(gl: WebGLRenderingContext, vertexSource: string, fragmentSource: string) {
  const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
  const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
  if (!vertexShader || !fragmentShader) return undefined;

  const program = gl.createProgram();
  if (!program) return undefined;
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);
  gl.deleteShader(vertexShader);
  gl.deleteShader(fragmentShader);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return undefined;
  }
  return program;
}

function compileShader(gl: WebGLRenderingContext, type: number, source: string) {
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
