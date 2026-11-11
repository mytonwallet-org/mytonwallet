import { createGlowProgram, ROUNDED_RECT_GLSL } from './agentEdgeGlowRenderer';

// The iOS field glow (`AgentFieldGlow.metal`) as a WebGL fragment shader: the lights inside the field and its
// glowing rim, drawn on one canvas that reaches beyond the field for the rim's bloom

/** Pixels per CSS pixel are capped, as on iOS */
const MAX_PIXEL_RATIO = 2;

const VERTEX_SHADER = `
attribute vec2 a_position;

void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const FRAGMENT_SHADER = `
precision highp float;

uniform vec2 u_size;
uniform float u_canvasHeight;
uniform float u_pixelRatio;
uniform float u_radius;
uniform float u_margin;
uniform float u_time;
uniform float u_leading;
uniform vec3 u_tint;

${ROUNDED_RECT_GLSL}

// A soft light spreading over sigma pixels
float getLight(vec2 xy, vec2 centre, float sigma) {
  vec2 d = xy - centre;
  return exp(-dot(d, d) / (2.0 * sigma * sigma));
}

// iOS's agentFieldGlowFragment, premultiplied, at full opacity: an edge band brightest at the bottom and the leading
// side, and three lights drifting along the bottom, through the field and up and down the leading side
vec4 getLights(vec2 xy, float distance, float time) {
  vec2 size = u_size;
  float leading = u_leading;
  float inset = max(-distance, 0.0);
  float leadingDistance = abs(xy.x / size.x - leading) * size.x;
  float down = xy.y / size.y;
  float edgeBand = exp(-inset / 5.0);
  float nearLeading = exp(-leadingDistance / 50.0);

  // A share of the width from the leading side is abs(leading - share) * size.x
  vec2 bottomCentre = vec2(abs(leading - (0.35 + 0.25 * sin(time * 0.55))) * size.x, size.y);
  vec2 driftCentre = vec2(
    abs(leading - (0.575 + 0.325 * sin(time * 0.37 + 2.0))) * size.x,
    size.y * (0.725 + 0.275 * sin(time * 0.8))
  );
  vec2 sideCentre = vec2(leading * size.x, size.y * (0.65 + 0.35 * sin(time * 0.45 + 1.0)));
  float bottomLight = getLight(xy, bottomCentre, 28.0);
  float driftLight = getLight(xy, driftCentre, 40.0);
  float sideLight = getLight(xy, sideCentre, 22.0);
  float haze = 0.3 * exp(-(size.y - xy.y) / 22.0) * (0.5 + 0.5 * nearLeading);
  float glow = edgeBand * (0.35 + 1.1 * nearLeading + 0.6 * down)
    * (0.7 + 0.9 * bottomLight + 0.5 * driftLight + 0.6 * sideLight)
    + 0.45 * bottomLight + 0.25 * driftLight + 0.35 * sideLight + haze;
  float alpha = clamp(glow * 0.55, 0.0, 0.92);
  // The brightest light whitens
  vec3 color = mix(u_tint, vec3(1.0), clamp((glow - 1.1) * 0.35, 0.0, 0.6));
  return vec4(color * alpha, alpha);
}

// A bright stretch of the rim centred centre pixels along a border total pixels long
float getRimSpot(float along, float centre, float total, float sigma) {
  float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
  return exp(-d * d / (2.0 * sigma * sigma));
}

// iOS's agentFieldRimFragment: a thin, almost white core line along the border, a bloom in the accent colour
// spilling out beyond the field and a softer haze inside it, brightest at the bottom and the leading side, with bright
// stretches running along it
vec4 getRim(vec2 xy, float distance, float time) {
  vec2 size = u_size;
  vec2 halfSize = size * 0.5;
  float total;
  float along = getBorderAlong(xy - halfSize, halfSize, u_radius, total);

  float down = clamp(xy.y / size.y, 0.0, 1.0);
  float nearLeading = exp(-abs(clamp(xy.x / size.x, 0.0, 1.0) - u_leading) * size.x / 90.0);
  float base = 0.15 + 0.45 * down + 0.6 * nearLeading;
  float spots = getRimSpot(along, time * 140.0, total, 60.0)
    + 0.8 * getRimSpot(along, total * 0.45 - time * 95.0, total, 48.0)
    + 0.6 * getRimSpot(along, total * 0.7 + time * 60.0, total, 70.0);
  float intensity = base * (0.3 + 1.2 * spots);

  float core = exp(-distance * distance / (2.0 * 0.6 * 0.6));
  // The bloom spreads out over a few pixels and fades on over more, and the haze inside is softer
  float outer = distance > 0.0 ? exp(-distance / 7.0) + 0.35 * exp(-distance / 18.0) : 0.0;
  // It is gone by the canvas's edge
  outer *= 1.0 - smoothstep(0.5 * u_margin, u_margin, distance);
  float inner = distance < 0.0 ? 0.45 * exp(distance / 9.0) : 0.0;
  float coreAlpha = clamp(core * intensity, 0.0, 1.0);
  float bloomAlpha = clamp((outer + inner) * intensity, 0.0, 0.9);
  // The core whitens the brighter it is
  vec3 coreColor = mix(u_tint, vec3(1.0), clamp(0.45 + 0.45 * intensity, 0.0, 0.9));
  vec3 bloomColor = mix(u_tint, vec3(1.0), 0.1);
  vec3 color = coreColor * coreAlpha + bloomColor * bloomAlpha * (1.0 - coreAlpha);
  return vec4(color, coreAlpha + bloomAlpha * (1.0 - coreAlpha));
}

void main() {
  vec2 point = vec2(gl_FragCoord.x, u_canvasHeight - gl_FragCoord.y) / u_pixelRatio;
  vec2 xy = point - u_margin;
  vec2 halfSize = u_size * 0.5;
  float distance = getRoundedRectDistance(xy - halfSize, halfSize, u_radius);
  // As on iOS, the lights show at half their strength and move twice as fast, inside the field, which clips them to
  // its rounded shape over a pixel; the rim lies over them
  float clip = clamp(0.5 - distance * u_pixelRatio, 0.0, 1.0);
  vec4 lights = getLights(xy, distance, u_time * 2.0) * (0.5 * clip);
  vec4 rim = getRim(xy, distance, u_time);
  gl_FragColor = rim + lights * (1.0 - rim.a);
}
`;

/** The field's box and the canvas's, in CSS pixels; the canvas reaches `margin` beyond the field on every side */
export interface AgentFieldGlowGeometry {
  width: number;
  height: number;
  cornerRadius: number;
  margin: number;
}

interface AgentFieldGlowRenderer {
  resize: (geometry: AgentFieldGlowGeometry) => void;
  /** Draws the glow `time` seconds after it came in, in the accent colour `tint` (RGB, 0 to 1) */
  render: (time: number, tint: [number, number, number], isRtl: boolean) => void;
  destroy: NoneToVoidFunction;
}

export function createAgentFieldGlowRenderer(canvas: HTMLCanvasElement): AgentFieldGlowRenderer | undefined {
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
  const canvasHeightLocation = gl.getUniformLocation(program, 'u_canvasHeight');
  const pixelRatioLocation = gl.getUniformLocation(program, 'u_pixelRatio');
  const radiusLocation = gl.getUniformLocation(program, 'u_radius');
  const marginLocation = gl.getUniformLocation(program, 'u_margin');
  const timeLocation = gl.getUniformLocation(program, 'u_time');
  const leadingLocation = gl.getUniformLocation(program, 'u_leading');
  const tintLocation = gl.getUniformLocation(program, 'u_tint');

  let field: AgentFieldGlowGeometry = {
    width: 0, height: 0, cornerRadius: 0, margin: 0,
  };
  let pixelRatio = 1;

  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  // Two triangles over the whole canvas
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
  gl.clearColor(0, 0, 0, 0);

  return {
    resize(geometry) {
      field = {
        ...geometry,
        cornerRadius: Math.min(geometry.cornerRadius, geometry.width / 2, geometry.height / 2),
      };
      pixelRatio = Math.min(MAX_PIXEL_RATIO, window.devicePixelRatio || 1);
      canvas.width = Math.max(1, Math.ceil((field.width + 2 * field.margin) * pixelRatio));
      canvas.height = Math.max(1, Math.ceil((field.height + 2 * field.margin) * pixelRatio));
      gl.viewport(0, 0, canvas.width, canvas.height);
    },

    render(time, tint, isRtl) {
      gl.clear(gl.COLOR_BUFFER_BIT);
      if (field.width <= 0 || field.height <= 0) return;
      gl.uniform2f(sizeLocation, field.width, field.height);
      gl.uniform1f(canvasHeightLocation, canvas.height);
      gl.uniform1f(pixelRatioLocation, pixelRatio);
      gl.uniform1f(radiusLocation, field.cornerRadius);
      gl.uniform1f(marginLocation, field.margin);
      gl.uniform1f(timeLocation, time);
      gl.uniform1f(leadingLocation, isRtl ? 1 : 0);
      gl.uniform3f(tintLocation, tint[0], tint[1], tint[2]);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
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
