import type { CardArtworkLayers } from './cardSvgLayers';

import {
  CARD_ARTWORK_HEIGHT, CARD_ARTWORK_WIDTH, CARD_MAX_SPOTS, CARD_SPOT_PADDING,
} from './cardSvgLayers';

// The wave and spot motion match the native home card
const CARD_MOTION_STRENGTH = 15;
const CARD_MOTION_SPEED = 1.55;
/** One idle revolution of the color spots takes about 57 seconds */
const SPOT_REVOLUTIONS_PER_SECOND = 0.7 / 40;
/** Touch speeds the spots up to three times, quickly on press and slowly on release */
const BOOST_ATTACK_SECONDS = 0.12;
const BOOST_DECAY_SECONDS = 0.65;
const BOOST_REST_THRESHOLD = 0.001;

/** The slow wave needs only 30 frames per second, limiting GPU work */
export const CARD_MOTION_FPS = 30;
/** Touch response and its settling tail render at full rate, as on the native card */
export const CARD_MOTION_BOOST_FPS = 60;

/** Cap the drawing buffer at 800 device pixels wide to limit GPU memory and drawing cost */
const MAX_DRAWABLE_WIDTH = 800;

const VERTEX_SHADER = `
attribute vec2 a_position;
varying vec2 v_uv;

void main() {
  v_uv = (a_position + 1.0) * 0.5;
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

/**
 * At \`u_time = 0\`, the shader leaves the artwork undistorted.
 * The wave fades to zero at every edge, keeping the card outline fixed.
 * The color spots are not distorted: they rotate around the card center as whole layers,
 * and the text-contrast gradient stays fixed above them.
 */
const FRAGMENT_SHADER = `
precision mediump float;

uniform sampler2D u_artwork;
uniform sampler2D u_spot0;
uniform sampler2D u_spot1;
uniform sampler2D u_spot2;
uniform int u_spotCount;
uniform vec2 u_size;
uniform float u_time;
uniform float u_spotAngle;
uniform float u_strength;
uniform float u_seed;
uniform float u_contrastColor;
uniform float u_contrastOpacity;
// The image and card can have different aspect ratios, so crop the image to fill the card
uniform vec2 u_coverScale;
uniform vec2 u_coverOffset;

varying vec2 v_uv;

const float PI = 3.1415926535897932;
const vec2 ARTWORK_SIZE = vec2(${CARD_ARTWORK_WIDTH}.0, ${CARD_ARTWORK_HEIGHT}.0);
const vec2 SPOT_PADDING = vec2(${CARD_SPOT_PADDING}.0);

vec2 spotUv(vec2 point) {
  float c = cos(u_spotAngle);
  float s = sin(u_spotAngle);
  vec2 centered = point - ARTWORK_SIZE * 0.5;
  vec2 rotated = vec2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y) + ARTWORK_SIZE * 0.5;
  vec2 uv = (rotated + SPOT_PADDING) / (ARTWORK_SIZE + 2.0 * SPOT_PADDING);
  return vec2(uv.x, 1.0 - uv.y);
}

vec3 blendSpot(vec3 color, vec4 spot) {
  return spot.rgb + color * (1.0 - spot.a);
}

void main() {
  vec2 position = v_uv * u_size;
  vec2 edge = sin(PI * clamp(v_uv, 0.0, 1.0));
  float envelope = edge.x * edge.y;
  float phase = u_seed * 2.0 * PI;
  vec2 wave = vec2(
    sin(u_time * 0.7 + v_uv.y * 5.0 + phase) - sin(v_uv.y * 5.0 + phase),
    sin(u_time * 0.53 + v_uv.x * 4.0 + phase) - sin(v_uv.x * 4.0 + phase)
  );
  vec2 displaced = position + wave * envelope * u_strength * u_size.x / 400.0;
  vec2 uv = displaced / max(u_size, vec2(1.0));
  vec4 base = texture2D(u_artwork, (uv * u_coverScale) + u_coverOffset);
  vec3 color = base.rgb;

  // Generator coordinates with y pointing down, as in the SVG
  vec2 point = vec2(v_uv.x, 1.0 - v_uv.y) * ARTWORK_SIZE;
  if (u_spotCount > 0) color = blendSpot(color, texture2D(u_spot0, spotUv(point)));
  if (u_spotCount > 1) color = blendSpot(color, texture2D(u_spot1, spotUv(point)));
  if (u_spotCount > 2) color = blendSpot(color, texture2D(u_spot2, spotUv(point)));

  if (u_contrastColor >= 0.0) {
    float radius = length((point - ARTWORK_SIZE * 0.5) / vec2(269.69, 158.0));
    float alpha = radius < 0.25 ? 1.0 - radius * 0.8
      : radius < 0.75 ? 1.1 - radius * 1.2 : max(0.0, 0.8 - radius * 0.8);
    vec3 overlay = mix(
      1.0 - 2.0 * (1.0 - color) * (1.0 - u_contrastColor),
      2.0 * color * u_contrastColor,
      step(color, vec3(0.5))
    );
    color = mix(color, overlay, alpha * u_contrastOpacity);
    color = mix(color, vec3(u_contrastColor), alpha * 0.16);
  }

  // Transparent parts of the artwork stay transparent, so the still image below shows through them
  gl_FragColor = vec4(color * base.a, base.a);
}
`;

interface CardMotionSize {
  cssWidth: number;
  cssHeight: number;
}

interface CardMotionRenderer {
  draw: (timeSeconds: number, spotTimeSeconds: number) => void;
  measure: () => CardMotionSize | undefined;
  applySize: (size: CardMotionSize) => void;
  destroy: NoneToVoidFunction;
}

/** Derives a stable wave phase from the NFT address so its motion stays the same across renders */
export function getCardMotionSeed(key: string) {
  let hash = 2166136261;
  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }

  return (hash >>> 0) % 65536 / 65536;
}

/**
 * Advances the wave and spot clocks. Pressing the card speeds the spots up smoothly, and the speed
 * is integrated into their phase, so a press never makes them jump.
 */
export function createCardMotionClock() {
  let waveTime = 0;
  let spotTime = 0;
  let boost = 0;

  return {
    get waveTime() {
      return waveTime;
    },
    get spotTime() {
      return spotTime;
    },
    get isBoosting() {
      return boost > BOOST_REST_THRESHOLD;
    },
    advance(elapsedSeconds: number, press: number) {
      const target = Math.min(1, Math.max(0, press));
      const response = target > boost ? BOOST_ATTACK_SECONDS : BOOST_DECAY_SECONDS;
      const decay = Math.exp(-elapsedSeconds / response);
      const integratedBoost = target * elapsedSeconds + (boost - target) * response * (1 - decay);
      waveTime += elapsedSeconds * CARD_MOTION_SPEED;
      spotTime += elapsedSeconds + 2 * integratedBoost;
      boost = target + (boost - target) * decay;
    },
  };
}

export function createCardMotionRenderer(
  canvas: HTMLCanvasElement,
  layers: CardArtworkLayers,
  seed: number,
): CardMotionRenderer | undefined {
  const gl = canvas.getContext('webgl', { alpha: true, antialias: false, premultipliedAlpha: true });
  if (!gl) return undefined;

  const program = buildProgram(gl);
  if (!program) return undefined;

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  // One oversized triangle covers the entire canvas
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);

  const positionLocation = gl.getAttribLocation(program, 'a_position');
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

  const { base, spots, contrastColor, contrastOpacity } = layers;
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  const textures = [base, ...spots.slice(0, CARD_MAX_SPOTS)].map((image, index) => {
    gl.activeTexture(gl.TEXTURE0 + index);
    // Spot layers are blended as premultiplied color, the same way a canvas composites them
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, index > 0);
    return uploadTexture(gl, image);
  });
  // Every spot sampler needs a bound texture even when the shader skips it, or the draw call is flagged
  for (let index = textures.length; index <= CARD_MAX_SPOTS; index++) {
    gl.activeTexture(gl.TEXTURE0 + index);
    gl.bindTexture(gl.TEXTURE_2D, textures[0]);
  }

  gl.useProgram(program);
  gl.uniform1i(gl.getUniformLocation(program, 'u_artwork'), 0);
  for (let index = 0; index < CARD_MAX_SPOTS; index++) {
    gl.uniform1i(gl.getUniformLocation(program, `u_spot${index}`), index + 1);
  }
  gl.uniform1i(gl.getUniformLocation(program, 'u_spotCount'), textures.length - 1);
  gl.uniform1f(gl.getUniformLocation(program, 'u_strength'), CARD_MOTION_STRENGTH);
  gl.uniform1f(gl.getUniformLocation(program, 'u_seed'), seed);
  gl.uniform1f(gl.getUniformLocation(program, 'u_contrastColor'), contrastColor);
  gl.uniform1f(gl.getUniformLocation(program, 'u_contrastOpacity'), contrastOpacity);

  const sizeLocation = gl.getUniformLocation(program, 'u_size');
  const timeLocation = gl.getUniformLocation(program, 'u_time');
  const spotAngleLocation = gl.getUniformLocation(program, 'u_spotAngle');
  const coverScaleLocation = gl.getUniformLocation(program, 'u_coverScale');
  const coverOffsetLocation = gl.getUniformLocation(program, 'u_coverOffset');

  function measure() {
    const cssWidth = canvas.clientWidth;
    const cssHeight = canvas.clientHeight;

    return cssWidth && cssHeight ? { cssWidth, cssHeight } : undefined;
  }

  function applySize({ cssWidth, cssHeight }: CardMotionSize) {
    const ratio = Math.min(window.devicePixelRatio || 1, MAX_DRAWABLE_WIDTH / cssWidth);
    const width = Math.round(cssWidth * ratio);
    const height = Math.round(cssHeight * ratio);

    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }

    gl!.viewport(0, 0, width, height);
    // Use CSS pixels so the wave has the same shape at every device pixel ratio
    gl!.uniform2f(sizeLocation, cssWidth, cssHeight);

    const cardAspect = cssWidth / cssHeight;
    const imageAspect = base.naturalWidth / base.naturalHeight;
    const scaleX = imageAspect > cardAspect ? cardAspect / imageAspect : 1;
    const scaleY = imageAspect > cardAspect ? 1 : imageAspect / cardAspect;
    gl!.uniform2f(coverScaleLocation, scaleX, scaleY);
    gl!.uniform2f(coverOffsetLocation, (1 - scaleX) / 2, (1 - scaleY) / 2);
  }

  return {
    measure,
    applySize,
    draw(timeSeconds: number, spotTimeSeconds: number) {
      gl.uniform1f(timeLocation, timeSeconds);
      gl.uniform1f(spotAngleLocation, spotTimeSeconds * SPOT_REVOLUTIONS_PER_SECOND * 2 * Math.PI);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
    destroy() {
      textures.forEach((texture) => gl.deleteTexture(texture));
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    },
  };
}

function uploadTexture(gl: WebGLRenderingContext, image: HTMLImageElement) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  // Clamp edges and avoid mipmaps so non-power-of-two artwork works in WebGL 1
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);

  return texture;
}

function buildProgram(gl: WebGLRenderingContext) {
  const vertex = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
  if (!vertex || !fragment) return undefined;

  const program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  // The linked program retains the shaders, so their handles can be released
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return undefined;
  }

  return program;
}

function compileShader(gl: WebGLRenderingContext, type: number, source: string) {
  const shader = gl.createShader(type)!;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);

  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return undefined;
  }

  return shader;
}
