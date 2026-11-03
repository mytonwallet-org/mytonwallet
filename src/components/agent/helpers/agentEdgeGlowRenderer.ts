// The iOS edge glow (`AgentEdgeGlow.metal`) as a WebGL fragment shader, drawn over four strips along the edges

/** How far in from the rounded edge the glow reaches, in CSS pixels */
const GLOW_DEPTH = 30;
/** Pixels per CSS pixel are capped, as on iOS */
const MAX_PIXEL_RATIO = 2;

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
uniform float u_isDark;

float getRoundedRectDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// One colour blob along the perimeter: cos² over a little less than half of the loop
float getBlob(float p, float centre) {
  float dp = abs(fract(p - centre + 0.5) - 0.5);
  const float halfWidth = 0.2375;
  if (dp >= halfWidth) return 0.0;
  float c = cos(1.5707963 * dp / halfWidth);
  return c * c;
}

void main() {
  vec2 point = vec2(gl_FragCoord.x, u_size.y * u_pixelRatio - gl_FragCoord.y) / u_pixelRatio;
  vec2 halfSize = u_size * 0.5;
  vec2 local = point - halfSize;
  float distance = getRoundedRectDistance(local, halfSize, u_radius);
  float inset = -distance;
  if (inset > 30.0) {
    gl_FragColor = vec4(0.0);
    return;
  }
  // Nothing shows past the rounded edge, which is smoothed over a pixel
  float edge = clamp(0.5 - distance * u_pixelRatio, 0.0, 1.0);
  inset = max(inset, 0.0);

  // Radial projection onto the unit square: every side takes the same share of the loop, clockwise from the middle
  // of the top edge (0) through the right (0.25), the bottom (0.5) and the left (0.75)
  vec2 uv = local / u_size;
  vec2 s = uv / max(max(abs(uv.x), abs(uv.y)), 1e-5) * 0.5;
  bool isVerticalSide = abs(s.x) >= abs(s.y);
  float p;
  if (!isVerticalSide && s.y < 0.0) {
    p = s.x * 0.25;
    if (p < 0.0) p += 1.0;
  } else if (isVerticalSide && s.x > 0.0) {
    p = 0.125 + (s.y + 0.5) * 0.25;
  } else if (!isVerticalSide) {
    p = 0.375 + (0.5 - s.x) * 0.25;
  } else {
    p = 0.625 + (0.5 - s.y) * 0.25;
  }

  // A full loop takes 2.667 s; the purple blob runs half a loop behind the blue one
  float blueCentre = fract(u_time / 2.667 + 0.125);
  float blue = getBlob(p, blueCentre);
  float purple = getBlob(p, blueCentre + 0.5);
  float weight = min(1.0, blue + purple);

  // Gaussian falloff inward (sigma 8 px). The long sides are dimmer except near the corners, and within about one
  // corner radius of a corner the glow is a quarter brighter than its colour, as a blurred stroke is there
  const float sigma = 8.0;
  float falloff = exp(-(inset * inset) / (2.0 * sigma * sigma));
  bool isLongSide = isVerticalSide == (u_size.y >= u_size.x);
  float alongEdge = max(halfSize.x - abs(local.x), halfSize.y - abs(local.y));
  float cornerZone = max(u_radius, 24.0);
  float corner = 1.0 - smoothstep(0.25 * cornerZone, cornerZone, alongEdge);
  float sideGain = isLongSide ? 0.8 + 0.2 * (1.0 - smoothstep(20.0, 90.0, alongEdge)) : 1.0;
  float intensity = falloff * sideGain * (1.0 + 0.25 * corner);

  vec4 color;
  if (u_isDark > 0.5) {
    vec3 blueColor = vec3(5.0, 109.0, 205.0) / 255.0;
    vec3 purpleColor = vec3(144.0, 70.0, 203.0) / 255.0;
    vec3 blobColor = (blueColor * blue + purpleColor * purple) / max(blue + purple, 1e-4);
    // Between the blobs the content shows through; above full intensity the colour itself brightens
    float strength = intensity * weight;
    color = vec4(blobColor * strength, min(strength, 1.0));
  } else {
    vec3 blueColor = vec3(50.0, 158.0, 255.0) / 255.0;
    vec3 purpleColor = vec3(190.0, 118.0, 253.0) / 255.0;
    vec3 haze = vec3(244.0, 245.0, 252.0) / 255.0;
    vec3 blobColor = (blueColor * blue + purpleColor * purple) / max(blue + purple, 1e-4);
    // Between the blobs a white haze runs along the edge; above full intensity the colour deepens away from it
    float coverage = 0.95 * intensity;
    vec3 band = clamp(mix(haze, blobColor, weight * max(coverage, 1.0)), 0.0, 1.0);
    float alpha = min(coverage, 1.0);
    color = vec4(band * alpha, alpha);
  }
  gl_FragColor = color * edge;
}
`;

export interface AgentEdgeGlowRenderer {
  /** Fits the drawing to the glow's box, in CSS pixels, with the radius of its rounded corners */
  resize: (width: number, height: number, cornerRadius: number) => void;
  render: (time: number, isDark: boolean) => void;
  destroy: NoneToVoidFunction;
}

export function createAgentEdgeGlowRenderer(canvas: HTMLCanvasElement): AgentEdgeGlowRenderer | undefined {
  // Without a usable GPU, the browser renders WebGL on the CPU, and the CSS glow costs less
  const gl = canvas.getContext('webgl', {
    alpha: true, premultipliedAlpha: true, antialias: false, depth: false, failIfMajorPerformanceCaveat: true,
  });
  if (!gl) return undefined;

  const program = createProgram(gl);
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
  const isDarkLocation = gl.getUniformLocation(program, 'u_isDark');

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
      gl.uniform2f(sizeLocation, width, height);
      gl.uniform1f(pixelRatioLocation, pixelRatio);
      gl.uniform1f(radiusLocation, radius);
      gl.uniform1f(timeLocation, time);
      gl.uniform1f(isDarkLocation, isDark ? 1 : 0);
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
// whose inner edge is a quarter circle reaching furthest on the diagonal
function buildStripVertices(width: number, height: number, radius: number) {
  const innerRadius = Math.max(0, radius - GLOW_DEPTH);
  const depth = Math.ceil(Math.max(GLOW_DEPTH, radius - innerRadius * 0.7071)) + 2;
  const stripDepthX = Math.min(depth, width);
  const stripDepthY = Math.min(depth, height);
  const sideHeight = Math.max(0, height - 2 * depth);
  const rects = [
    [0, 0, width, stripDepthY],
    [width - stripDepthX, depth, stripDepthX, sideHeight],
    [0, height - stripDepthY, width, stripDepthY],
    [0, depth, stripDepthX, sideHeight],
  ].filter(([, , rectWidth, rectHeight]) => rectWidth > 0 && rectHeight > 0);

  return new Float32Array(rects.flatMap(([x, y, rectWidth, rectHeight]) => [
    x, y, x + rectWidth, y, x, y + rectHeight,
    x, y + rectHeight, x + rectWidth, y, x + rectWidth, y + rectHeight,
  ]));
}

function createProgram(gl: WebGLRenderingContext) {
  const vertexShader = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
  const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
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
