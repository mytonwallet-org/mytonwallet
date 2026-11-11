import type { CancellableCallback } from '../../util/PostMessageConnector';

import { ungzip } from '../../util/compression';
import { createPostMessageInterface } from '../../util/createPostMessageInterface';
import { fetchWithTimeout } from '../../util/fetch';
import { logDebugError } from '../../util/logs';
import scalarWasmUrl from './tlottie-scalar.wasm?url';
import simdWasmUrl from './tlottie-simd.wasm?url';

// Raw wasm ABI of https://github.com/dkaraush/tlottie (`src/bindings/wasm.rs`)
interface TLottieExports {
  memory: WebAssembly.Memory;
  tlottie_alloc: (len: number) => number;
  tlottie_free: (ptr: number, len: number) => void;
  tlottie_new: (jsonPointer: number, jsonLength: number) => number;
  tlottie_drop: (instance: number) => void;
  tlottie_width: (instance: number) => number;
  tlottie_height: (instance: number) => number;
  tlottie_frame_rate: (instance: number) => number;
  tlottie_frame_count: (instance: number) => number;
  tlottie_render: (instance: number, frame: number, width: number, height: number, antialias: number) => number;
  tlottie_render_alpha8_color: (
    instance: number, frame: number, width: number, height: number, antialias: number, color: number,
  ) => number;
}

const HIGH_PRIORITY_MAX_FPS = 60;
const LOW_PRIORITY_MAX_FPS = 30;
const RGBA_BYTES_PER_PIXEL = 4;
// A function returning a `v128` constant, the probe of https://github.com/GoogleChromeLabs/wasm-feature-detect
const SIMD_PROBE_MODULE = new Uint8Array([
  0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11,
]);

let tlottiePromise: Promise<TLottieExports> | undefined;

async function loadTLottie() {
  // Safari before 16.4 and Chrome before 91 cannot compile the SIMD build
  const wasmUrl = WebAssembly.validate(SIMD_PROBE_MODULE) ? simdWasmUrl : scalarWasmUrl;
  let result: WebAssembly.WebAssemblyInstantiatedSource;
  try {
    result = await WebAssembly.instantiateStreaming(fetch(wasmUrl), {});
  } catch (err) {
    // Servers that do not send `application/wasm` make streaming compilation fail, and `fetch` rejects
    // the `file:` URLs of the Electron app that runs its bundled copy
    result = await WebAssembly.instantiate(await readBinary(wasmUrl), {});
  }

  return result.instance.exports as unknown as TLottieExports;
}

function readBinary(url: string) {
  return new Promise<ArrayBuffer>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', url);
    xhr.responseType = 'arraybuffer';
    xhr.onload = () => {
      // A `file:` response has status 0
      if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)) {
        resolve(xhr.response as ArrayBuffer);
      } else {
        reject(new Error(`[TLottie] Failed to load ${url}: ${xhr.status}`));
      }
    };
    xhr.onerror = () => reject(new Error(`[TLottie] Failed to load ${url}`));
    xhr.send();
  });
}

function ensureTLottie() {
  if (!tlottiePromise) {
    tlottiePromise = loadTLottie();
    // A failed download is retried by the next request instead of failing every sticker until reload
    tlottiePromise.catch(() => {
      tlottiePromise = undefined;
    });
  }

  return tlottiePromise;
}

const renderers = new Map<string, {
  imgSize: number;
  reduceFactor: number;
  instance: number;
  frame: Frame;
  imageData: ImageData;
  customColor?: [number, number, number];
}>();

// Where the composition lands in the square image: scaled to fit and centered, keeping its aspect ratio
interface Frame {
  width: number;
  height: number;
  left: number;
  top: number;
}

// Incoming messages are processed at the same time, so `changeData` or `destroy` can start
// while `init` is still waiting for the network and has not saved its renderer yet.
// Operations for one key run one by one, so each of them sees the renderer
// that the previous one created.
const operationQueues = new Map<string, Promise<unknown>>();

function serialize<T extends (key: string, ...args: any[]) => any>(operation: T) {
  return (...args: Parameters<T>): Promise<Awaited<ReturnType<T>>> => {
    const key: string = args[0];
    const result = (operationQueues.get(key) ?? Promise.resolve())
      .then(() => (operation as AnyFunction)(...args));
    const tail = result.catch(() => undefined).then(() => {
      if (operationQueues.get(key) === tail) {
        operationQueues.delete(key);
      }
    });

    operationQueues.set(key, tail);

    return result;
  };
}

async function init(
  key: string,
  tgsUrl: string,
  imgSize: number,
  isLowPriority: boolean,
  customColor: [number, number, number] | undefined,
  onInit: CancellableCallback,
) {
  const api = await ensureTLottie();
  const instance = createInstance(api, await extractJson(tgsUrl));
  const imageData = new ImageData(imgSize, imgSize);

  const { reduceFactor, msPerFrame, reducedFramesCount } = calcParams(api, instance, isLowPriority);

  renderers.set(key, {
    imgSize, reduceFactor, instance, frame: fitFrame(api, instance, imgSize), imageData, customColor,
  });

  onInit(reduceFactor, msPerFrame, reducedFramesCount);
}

async function changeData(
  key: string,
  tgsUrl: string,
  isLowPriority: boolean,
  onInit: CancellableCallback,
) {
  const api = await ensureTLottie();
  const json = await extractJson(tgsUrl);
  const renderer = renderers.get(key);
  // The renderer is missing only if it was destroyed. An error here makes the request fail
  // on the main thread, which clears `isChangingData`. While that flag is set, no new
  // frames are requested.
  if (!renderer) {
    throw new Error(`[TLottie] No renderer for "${key}"`);
  }

  const instance = createInstance(api, json);
  api.tlottie_drop(renderer.instance);
  renderer.instance = instance;
  renderer.frame = fitFrame(api, instance, renderer.imgSize);

  const { reduceFactor, msPerFrame, reducedFramesCount } = calcParams(api, instance, isLowPriority);
  renderer.reduceFactor = reduceFactor;

  onInit(reduceFactor, msPerFrame, reducedFramesCount);
}

async function extractJson(tgsUrl: string) {
  // Failures propagate, so the sticker keeps its preview instead of reporting an empty animation as loaded
  const response = await fetchWithTimeout(tgsUrl);

  if (!response.ok) {
    throw new Error(`[TLottie] Failed to load ${tgsUrl}: ${response.status}`);
  }

  const contentType = response.headers.get('Content-Type')?.split(';')[0];
  if (contentType === 'application/json') {
    return response.text();
  }

  try {
    const arrayBuffer = await response.arrayBuffer();
    const inflated = await ungzip(arrayBuffer);
    return new TextDecoder().decode(inflated);
  } catch (err: any) {
    logDebugError('[extractJson] decompression error:', err?.message, err);

    throw err;
  }
}

function createInstance(api: TLottieExports, json: string) {
  // TLottie skips image layers, so such an animation would play with holes; failing here keeps the preview
  if (hasImageLayers(JSON.parse(json))) {
    throw new Error('[TLottie] Image layers are not supported');
  }

  const bytes = new TextEncoder().encode(json);
  const jsonPointer = api.tlottie_alloc(bytes.length);
  if (!jsonPointer) {
    throw new Error('[TLottie] Failed to allocate animation data');
  }

  // A view of `memory.buffer` is detached whenever the module grows its memory, so it is taken
  // anew after every exported call
  new Uint8Array(api.memory.buffer).set(bytes, jsonPointer);
  const instance = api.tlottie_new(jsonPointer, bytes.length);
  api.tlottie_free(jsonPointer, bytes.length);

  if (!instance) {
    throw new Error('[TLottie] Failed to parse animation');
  }

  return instance;
}

const IMAGE_LAYER_TYPE = 2;

function hasImageLayers(animation: { layers?: { ty?: number }[]; assets?: { layers?: { ty?: number }[] }[] }) {
  return [animation.layers, ...(animation.assets ?? []).map(({ layers }) => layers)]
    .some((layers) => layers?.some(({ ty }) => ty === IMAGE_LAYER_TYPE));
}

function fitFrame(api: TLottieExports, instance: number, imgSize: number): Frame {
  const sourceWidth = api.tlottie_width(instance) || imgSize;
  const sourceHeight = api.tlottie_height(instance) || imgSize;
  const scale = imgSize / Math.max(sourceWidth, sourceHeight);
  const width = Math.max(1, Math.round(sourceWidth * scale));
  const height = Math.max(1, Math.round(sourceHeight * scale));

  return {
    width, height, left: Math.floor((imgSize - width) / 2), top: Math.floor((imgSize - height) / 2),
  };
}

function calcParams(api: TLottieExports, instance: number, isLowPriority: boolean) {
  const framesCount = api.tlottie_frame_count(instance);
  const maxFps = isLowPriority ? LOW_PRIORITY_MAX_FPS : HIGH_PRIORITY_MAX_FPS;
  const sourceFps = api.tlottie_frame_rate(instance) || maxFps;
  const reduceFactor = sourceFps % maxFps === 0 ? sourceFps / maxFps : 1;

  return {
    reduceFactor,
    msPerFrame: 1000 / (sourceFps / reduceFactor),
    reducedFramesCount: Math.ceil(framesCount / reduceFactor),
  };
}

async function renderFrames(
  key: string, frameIndex: number, onProgress: CancellableCallback,
) {
  const api = await ensureTLottie();

  const renderer = renderers.get(key);
  if (!renderer) return;

  const {
    imgSize, reduceFactor, instance, frame: { width, height, left, top }, imageData, customColor,
  } = renderer;

  const realIndex = frameIndex * reduceFactor;

  const pixelsPointer = customColor
    ? api.tlottie_render_alpha8_color(instance, realIndex, width, height, 1, packColor(customColor))
    : api.tlottie_render(instance, realIndex, width, height, 1);
  if (!pixelsPointer) return;

  const pixels = new Uint8Array(api.memory.buffer, pixelsPointer, width * height * RGBA_BYTES_PER_PIXEL);
  if (width === imgSize && height === imgSize) {
    imageData.data.set(pixels);
  } else {
    imageData.data.fill(0);
    const rowBytes = width * RGBA_BYTES_PER_PIXEL;
    for (let row = 0; row < height; row++) {
      imageData.data.set(
        pixels.subarray(row * rowBytes, (row + 1) * rowBytes),
        ((top + row) * imgSize + left) * RGBA_BYTES_PER_PIXEL,
      );
    }
  }

  const imageBitmap = await createImageBitmap(imageData);

  onProgress(frameIndex, imageBitmap);
}

function packColor([red, green, blue]: [number, number, number]) {
  return (red << 16) | (green << 8) | blue;
}

function setColor(key: string, customColor: [number, number, number] | undefined) {
  const renderer = renderers.get(key);
  if (!renderer) return;

  renderer.customColor = customColor;
}

async function destroy(key: string) {
  const renderer = renderers.get(key);
  if (!renderer) return;

  (await ensureTLottie()).tlottie_drop(renderer.instance);
  renderers.delete(key);
}

const api = {
  'tlottie:init': serialize(init),
  'tlottie:changeData': serialize(changeData),
  'tlottie:renderFrames': serialize(renderFrames),
  'tlottie:setColor': setColor,
  'tlottie:destroy': serialize(destroy),
};

createPostMessageInterface(api);

export type TLottieApi = typeof api;
