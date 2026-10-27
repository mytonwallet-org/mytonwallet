import type { SurfaceFrame } from './surfaceLight';
import type { CardArtworkLayers } from './svgLayers';

import { getCardBrushTexture } from './brushTexture';
import fragmentSource from './surface.frag?raw';
import { sameBackgroundKey, surfaceBackgroundKey } from './surfaceCache';
import { getCardTouchGlowTexture } from './touchGlowTexture';

export interface CardSurfaceProfile {
  isCustom: boolean;
  isGram: boolean;
  /** Shader material: 0 for standard cards, 1 for silver, gold and platinum, 2 for black */
  material: number;
  intensity: number;
  seed: number;
  shineOpacity: number;
  gramWidth: number;
  gramBlur: number;
}

export type { SurfaceFrame } from './surfaceLight';

function compile(gl: WebGL2RenderingContext, type: number, source: string) {
  const s = gl.createShader(type)!;
  gl.shaderSource(s, source);
  gl.compileShader(s);

  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    const message = gl.getShaderInfoLog(s);
    gl.deleteShader(s);
    throw new Error(message || 'Shader compilation failed');
  }

  return s;
}

export function surfaceRenderer(
  canvas: HTMLCanvasElement,
  profile: CardSurfaceProfile,
  layers: CardArtworkLayers,
  initialWidth: number,
) {
  const context = canvas.getContext('webgl2', {
    alpha: false,
    antialias: false,
    premultipliedAlpha: true,
    // The privacy fields and the card switch read the last drawn frame back at any time
    preserveDrawingBuffer: true,
  });

  if (!context) {
    throw new Error('WebGL 2 unavailable');
  }

  const gl = context;
  const images = [layers.base, ...layers.spots];
  const contrastOpacity = layers.contrastOpacity;
  const p = gl.createProgram();
  const shaders = [
    compile(
      gl,
      gl.VERTEX_SHADER,
      `#version 300 es
      in vec2 position;out vec2 v_uv;
      void main(){v_uv=vec2((position.x+1.0)*.5,(1.0-position.y)*.5);gl_Position=vec4(position,0,1);}`,
    ),
    compile(gl, gl.FRAGMENT_SHADER, fragmentSource),
  ];
  shaders.forEach((s) => gl.attachShader(p, s));
  gl.linkProgram(p);
  shaders.forEach((s) => gl.deleteShader(s));

  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(p) || 'Shader link failed');
  }

  gl.useProgram(p);

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);

  const loc = gl.getAttribLocation(p, 'position');
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

  const locations = new Map<string, WebGLUniformLocation | null>();
  const location = (name: string) => {
    if (!locations.has(name)) {
      locations.set(name, gl.getUniformLocation(p, name));
    }

    return locations.get(name)!;
  };
  const textures: WebGLTexture[] = [];
  let textureRevision = 0;

  function upload(image: TexImageSource, index: number, isPremultiplied = false) {
    const t = gl.createTexture();
    textures.push(t);
    gl.activeTexture(gl.TEXTURE0 + index);
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, isPremultiplied);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    textureRevision++;
  }

  upload(images[0], 0);

  // The shader skips missing spots by `spotCount`, so their slots get an empty texture instead of an artwork copy
  for (let i = 1; i <= 3; i++) {
    upload(images[i] ?? new ImageData(1, 1), i, true);
  }

  // The glow texture depends on the card width and is slow to build, so it is built for the real size right away
  let touchWidth = initialWidth;
  const touch = getCardTouchGlowTexture(touchWidth)!;
  let touchExtent = touch.extent;
  upload(touch.canvas, 4);
  upload(profile.isGram ? getCardBrushTexture() : new ImageData(1, 1), 5);

  ['u_artwork', 'u_spot0', 'u_spot1', 'u_spot2', 'u_touch', 'u_brush'].forEach((name, i) =>
    gl.uniform1i(location(name), i),
  );

  gl.uniform1i(location('customSurface'), Number(profile.isCustom));
  gl.uniform1i(location('gram'), Number(profile.isGram));
  gl.uniform1i(location('spotCount'), layers.spots.length);
  gl.uniform1i(location('materialPreset'), profile.material);
  gl.uniform1f(location('intensity'), profile.intensity);
  gl.uniform1f(location('seed'), profile.seed);
  gl.uniform1f(location('shine'), profile.shineOpacity);
  gl.uniform2f(location('gramShape'), profile.gramWidth, profile.gramBlur);
  gl.uniform1f(location('contrastColor'), layers.contrastColor);
  gl.uniform1f(location('contrastOpacity'), contrastOpacity);
  gl.uniform1f(location('touchExtent'), touch.extent);

  const backdrop = profile.isGram ? gl.createTexture() : undefined;
  const framebuffer = profile.isGram ? gl.createFramebuffer() : undefined;

  if (backdrop) {
    gl.activeTexture(gl.TEXTURE6);
    gl.bindTexture(gl.TEXTURE_2D, backdrop);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.uniform1i(location('u_backdrop'), 6);
  }

  let cacheKey: number[] | undefined;
  let drawableWidth = 0;
  let drawableHeight = 0;
  let isDestroyed = false;

  function updateTouchTexture(source: TexImageSource, extent: number) {
    if (isDestroyed || gl.isContextLost()) return;

    gl.activeTexture(gl.TEXTURE4);
    gl.bindTexture(gl.TEXTURE_2D, textures[4]);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    touchExtent = extent;
    textureRevision++;
    cacheKey = undefined;
  }

  return {
    draw(frame: SurfaceFrame, width: number, height: number, cornerRadius: number) {
      if (isDestroyed || gl.isContextLost()) {
        return false;
      }

      if (width !== touchWidth) {
        touchWidth = width;

        const texture = getCardTouchGlowTexture(width)!;
        updateTouchTexture(texture.canvas, texture.extent);
      }

      const ratio = Math.min(devicePixelRatio || 1, 800 / width);
      const w = Math.round(width * ratio);
      const h = Math.round(height * ratio);

      if (
        canvas.width !== w
        || canvas.height !== h
        || drawableWidth !== w
        || drawableHeight !== h
      ) {
        canvas.width = w;
        canvas.height = h;
        gl.viewport(0, 0, w, h);
        drawableWidth = w;
        drawableHeight = h;
        cacheKey = undefined;

        if (backdrop && framebuffer) {
          gl.activeTexture(gl.TEXTURE6);
          gl.bindTexture(gl.TEXTURE_2D, backdrop);
          // eslint-disable-next-line no-null/no-null
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
          gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
          gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, backdrop, 0);

          const isComplete = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
          // eslint-disable-next-line no-null/no-null
          gl.bindFramebuffer(gl.FRAMEBUFFER, null);

          if (!isComplete) {
            throw new Error('Card backdrop framebuffer unavailable');
          }
        }
      }

      gl.useProgram(p);
      gl.uniform2f(location('size'), width, height);
      gl.uniform1f(location('cornerRadius'), cornerRadius);
      gl.uniform1f(location('time'), frame.time);
      gl.uniform1f(location('blobTime'), frame.blobTime);
      gl.uniform2f(location('tilt'), frame.tilt[0], frame.tilt[1]);
      gl.uniform2f(location('touchPosition'), frame.touch[0], frame.touch[1]);
      gl.uniform1f(location('touchOpacity'), frame.touch[2]);
      gl.uniform1f(location('touchExtent'), frame.touchExtent ?? touchExtent);
      gl.uniform1f(location('gramRotation'), frame.gramRotation);
      gl.uniform1f(location('activity'), frame.activity);

      if (backdrop && framebuffer) {
        const key = surfaceBackgroundKey(
          { ...frame, touchExtent: frame.touchExtent ?? touchExtent },
          profile,
          [width, height, w, h, cornerRadius],
          layers.spots.length,
          textureRevision,
        );

        if (!sameBackgroundKey(cacheKey, key)) {
          // The backdrop is unbound while it is drawn into, since WebGL cannot read and write one texture at once
          gl.activeTexture(gl.TEXTURE6);
          gl.bindTexture(gl.TEXTURE_2D, textures[0]);
          gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
          gl.uniform1i(location('renderPass'), 1);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
          // eslint-disable-next-line no-null/no-null
          gl.bindFramebuffer(gl.FRAMEBUFFER, null);
          cacheKey = key;
        }

        gl.activeTexture(gl.TEXTURE6);
        gl.bindTexture(gl.TEXTURE_2D, backdrop);
        gl.uniform1i(location('renderPass'), 2);
      } else {
        gl.uniform1i(location('renderPass'), 0);
      }

      gl.drawArrays(gl.TRIANGLES, 0, 3);

      return true;
    },
    destroy() {
      isDestroyed = true;
      textures.forEach((t) => gl.deleteTexture(t));

      if (backdrop) {
        gl.deleteTexture(backdrop);
      }

      if (framebuffer) {
        gl.deleteFramebuffer(framebuffer);
      }

      gl.deleteBuffer(buffer);
      gl.deleteProgram(p);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    },
  };
}
