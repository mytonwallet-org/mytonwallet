import type { CancellableCallback } from '../../util/PostMessageConnector';

import { ungzip } from '../../util/compression';
import { createPostMessageInterface } from '../../util/createPostMessageInterface';
import { fetchWithTimeout } from '../../util/fetch';
import { logDebugError } from '../../util/logs';

declare const Module: any;

declare function allocate(...args: any[]): string;

declare function intArrayFromString(str: string): string;

declare const self: WorkerGlobalScope;

try {
  self.importScripts('rlottie-wasm.js');
} catch (err) {
  throw new Error('Failed to import rlottie-wasm.js');
}

let rLottieApi: Record<string, AnyFunction>;
const rLottieApiPromise = new Promise<void>((resolve) => {
  Module.onRuntimeInitialized = () => {
    rLottieApi = {
      init: Module.cwrap('lottie_init', '', []),
      destroy: Module.cwrap('lottie_destroy', '', ['number']),
      resize: Module.cwrap('lottie_resize', '', ['number', 'number', 'number']),
      buffer: Module.cwrap('lottie_buffer', 'number', ['number']),
      render: Module.cwrap('lottie_render', '', ['number', 'number']),
      loadFromData: Module.cwrap('lottie_load_from_data', 'number', ['number', 'number']),
    };

    resolve();
  };
});

const HIGH_PRIORITY_MAX_FPS = 60;
const LOW_PRIORITY_MAX_FPS = 30;
const LOTTIE_JSON_STUB = '{"tgs":1,"w":16,"h":16,"layers":[]}';

const renderers = new Map<string, {
  imgSize: number;
  reduceFactor: number;
  handle: any;
  imageData: ImageData;
  customColor?: [number, number, number];
}>();

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
  if (!rLottieApi) {
    await rLottieApiPromise;
  }

  const json = await extractJson(tgsUrl);
  const stringOnWasmHeap = allocate(intArrayFromString(json), 'i8', 0);
  const handle = rLottieApi.init();
  const framesCount = rLottieApi.loadFromData(handle, stringOnWasmHeap);
  rLottieApi.resize(handle, imgSize, imgSize);

  const imageData = new ImageData(imgSize, imgSize);

  const { reduceFactor, msPerFrame, reducedFramesCount } = calcParams(json, isLowPriority, framesCount);

  renderers.set(key, {
    imgSize, reduceFactor, handle, imageData, customColor,
  });

  onInit(reduceFactor, msPerFrame, reducedFramesCount);
}

async function changeData(
  key: string,
  tgsUrl: string,
  isLowPriority: boolean,
  onInit: CancellableCallback,
) {
  if (!rLottieApi) {
    await rLottieApiPromise;
  }

  const json = await extractJson(tgsUrl);
  const renderer = renderers.get(key);
  // The renderer is missing only if it was destroyed. An error here makes the request fail
  // on the main thread, which clears `isChangingData`. While that flag is set, no new
  // frames are requested.
  if (!renderer) {
    throw new Error(`[RLottie] No renderer for "${key}"`);
  }

  const stringOnWasmHeap = allocate(intArrayFromString(json), 'i8', 0);
  const framesCount = rLottieApi.loadFromData(renderer.handle, stringOnWasmHeap);

  const { reduceFactor, msPerFrame, reducedFramesCount } = calcParams(json, isLowPriority, framesCount);

  onInit(reduceFactor, msPerFrame, reducedFramesCount);
}

async function extractJson(tgsUrl: string) {
  const response = await fetchWithTimeout(tgsUrl);

  if (!response.ok) {
    return LOTTIE_JSON_STUB;
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

    return LOTTIE_JSON_STUB;
  }
}

function calcParams(json: string, isLowPriority: boolean, framesCount: number) {
  const animationData = JSON.parse(json);
  const maxFps = isLowPriority ? LOW_PRIORITY_MAX_FPS : HIGH_PRIORITY_MAX_FPS;
  const sourceFps = animationData.fr || maxFps;
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
  if (!rLottieApi) {
    await rLottieApiPromise;
  }

  const renderer = renderers.get(key);
  if (!renderer) return;

  const {
    imgSize, reduceFactor, handle, imageData, customColor,
  } = renderer;

  const realIndex = frameIndex * reduceFactor;

  rLottieApi.render(handle, realIndex);
  const bufferPointer = rLottieApi.buffer(handle);
  const data = Module.HEAPU8.subarray(bufferPointer, bufferPointer + (imgSize * imgSize * 4));

  if (customColor) {
    const arr = new Uint8ClampedArray(data);
    applyColor(arr, customColor);
    imageData.data.set(arr);
  } else {
    imageData.data.set(data);
  }

  const imageBitmap = await createImageBitmap(imageData);

  onProgress(frameIndex, imageBitmap);
}

function applyColor(arr: Uint8ClampedArray, color: [number, number, number]) {
  for (let i = 0; i < arr.length; i += 4) {
    arr[i] = color[0];
    arr[i + 1] = color[1];
    arr[i + 2] = color[2];
  }
}

function setColor(key: string, customColor: [number, number, number] | undefined) {
  const renderer = renderers.get(key);
  if (!renderer) return;

  renderer.customColor = customColor;
}

function destroy(key: string) {
  const renderer = renderers.get(key);
  if (!renderer) return;

  rLottieApi.destroy(renderer.handle);
  renderers.delete(key);
}

const api = {
  'rlottie:init': serialize(init),
  'rlottie:changeData': serialize(changeData),
  'rlottie:renderFrames': serialize(renderFrames),
  'rlottie:setColor': setColor,
  'rlottie:destroy': serialize(destroy),
};

createPostMessageInterface(api);

export type RLottieApi = typeof api;
