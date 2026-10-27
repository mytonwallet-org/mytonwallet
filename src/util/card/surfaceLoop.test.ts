import type { CardArtworkLayers } from './svgLayers';
import type { CardController } from './types';

import { logDebugError } from '../logs';
import { startCardSurface } from './surfaceLoop';
import { getCardSurfaceProfile } from './surfaceProfile';
import { surfaceRenderer } from './surfaceRenderer';

jest.mock('./surfaceRenderer', () => ({ surfaceRenderer: jest.fn() }));
jest.mock('../logs', () => ({ logDebugError: jest.fn() }));
jest.mock('../../hooks/useBackgroundMode', () => {
  const [getIsInBackground, setIsInBackground] = jest.requireActual('../signals').createSignal(false);

  return { getIsInBackground, setIsInBackground };
});

const { setIsInBackground } = jest.requireMock<{ setIsInBackground: (value: boolean) => void }>(
  '../../hooks/useBackgroundMode',
);

const callbacks = new Map<number, FrameRequestCallback>();
let nextId = 0;
let now = 0;
let stop: NoneToVoidFunction | undefined;

beforeEach(() => {
  callbacks.clear();
  now = 1000;
  setIsInBackground(false);

  jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
    callbacks.set(++nextId, cb);

    return nextId;
  });

  jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
    callbacks.delete(id);
  });

  jest.spyOn(performance, 'now').mockImplementation(() => now);
});

afterEach(() => {
  stop?.();
  stop = undefined;
  jest.clearAllMocks();
  jest.restoreAllMocks();
});

function frame() {
  now += 1000 / 60;

  const pending = [...callbacks.values()];
  callbacks.clear();
  pending.forEach((cb) => cb(now));
}

function mockRenderer(draw: () => boolean = () => true) {
  const renderer = { draw: jest.fn(draw), destroy: jest.fn() };
  jest.mocked(surfaceRenderer).mockReturnValue(renderer as unknown as ReturnType<typeof surfaceRenderer>);

  return renderer;
}

async function start(isDisabled = false, isGram = false) {
  const card = document.createElement('div');
  Object.defineProperties(card, { clientWidth: { value: 320 }, clientHeight: { value: 200 } });

  const canvas = document.createElement('canvas');
  const layers = Promise.resolve({ base: {}, spots: [], contrastColor: -1, contrastOpacity: 0 } as unknown as
    CardArtworkLayers);
  const controller: CardController = { cardRef: { current: card } };
  const onPresent = jest.fn();
  const onReadyChange = jest.fn();
  const loop = startCardSurface({
    canvas,
    card,
    profile: getCardSurfaceProfile(undefined, isGram),
    layers,
    controller,
    getIsDisabled: () => isDisabled,
    onPresent,
    onReadyChange,
  });
  stop = loop.stop;
  await layers;
  await Promise.resolve();

  return { canvas, controller, loop, onPresent, onReadyChange };
}

it('draws the first frame once the artwork loads and reports readiness', async () => {
  const renderer = mockRenderer();
  const { loop, onPresent, onReadyChange } = await start();
  expect(renderer.draw).not.toHaveBeenCalled();
  frame();
  expect(renderer.draw).toHaveBeenCalledWith(expect.anything(), 320, 200, 0);
  expect(onPresent).toHaveBeenCalledWith(expect.anything(), 320, 200);
  expect(onReadyChange).toHaveBeenCalledWith(true);
  expect(loop.isPresented).toBe(true);
});

it('falls back to the artwork on a lost context and rebuilds the renderer on the restored one', async () => {
  const renderer = mockRenderer();
  const { canvas, onReadyChange } = await start();
  frame();

  const lost = new Event('webglcontextlost', { cancelable: true });
  canvas.dispatchEvent(lost);
  expect(lost.defaultPrevented).toBe(true);
  expect(onReadyChange).toHaveBeenLastCalledWith(false);
  expect(callbacks.size).toBe(0);

  const drawCount = renderer.draw.mock.calls.length;
  canvas.dispatchEvent(new Event('webglcontextrestored'));
  await Promise.resolve();
  await Promise.resolve();
  expect(surfaceRenderer).toHaveBeenCalledTimes(2);
  frame();
  expect(renderer.draw).toHaveBeenCalledTimes(drawCount + 1);
  expect(onReadyChange).toHaveBeenLastCalledWith(true);
});

it('drops a renderer that throws while drawing', async () => {
  const renderer = mockRenderer(() => {
    throw new Error('Card backdrop framebuffer unavailable');
  });
  const { loop, onReadyChange } = await start();
  frame();
  expect(logDebugError).toHaveBeenCalledWith('CardSurface draw failed', expect.any(Error));
  expect(renderer.destroy).toHaveBeenCalled();
  expect(onReadyChange).not.toHaveBeenCalled();
  expect(loop.isPresented).toBe(false);
  expect(callbacks.size).toBe(0);
});

it('draws a single resting frame while motion is disabled', async () => {
  const renderer = mockRenderer();
  await start(true);
  for (let i = 0; i < 5; i++) frame();
  expect(renderer.draw).toHaveBeenCalledTimes(1);
  expect(callbacks.size).toBe(0);
});

it('stops drawing a default card at rest and wakes up on a press', async () => {
  const renderer = mockRenderer();
  const { controller, loop } = await start();
  for (let i = 0; i < 120; i++) frame();
  expect(callbacks.size).toBe(0);

  const drawCount = renderer.draw.mock.calls.length;

  controller.motion = {
    press: [0, 0, 0.5],
    light: { x: 0.2, y: 0.2, opacity: 1 },
    pointer: [0.4, 0.2],
    isPlaying: true,
  };

  loop.wake();
  frame();
  frame();
  expect(renderer.draw.mock.calls.length).toBeGreaterThan(drawCount);
});

it('pauses a moving Gram card while the app is in the background', async () => {
  const renderer = mockRenderer();
  await start(false, true);
  for (let i = 0; i < 10; i++) frame();
  expect(callbacks.size).toBe(1);

  setIsInBackground(true);
  frame();
  expect(callbacks.size).toBe(0);

  const drawCount = renderer.draw.mock.calls.length;
  frame();
  expect(renderer.draw).toHaveBeenCalledTimes(drawCount);

  setIsInBackground(false);
  expect(callbacks.size).toBe(1);
  frame();
  expect(renderer.draw.mock.calls.length).toBeGreaterThan(drawCount);
});

it('draws one still frame for a card that starts while the app is in the background', async () => {
  setIsInBackground(true);

  const renderer = mockRenderer();
  const { loop } = await start(false, true);
  for (let i = 0; i < 5; i++) frame();
  expect(renderer.draw).toHaveBeenCalledTimes(1);
  expect(loop.isPresented).toBe(true);
  expect(callbacks.size).toBe(0);
});
