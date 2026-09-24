import { useEffect, useRef } from '../../lib/teact/teact';

import { createCardMotionRenderer } from '../../util/cardBackgroundMotion';
import { loadCardArtworkLayers } from '../../util/cardSvgLayers';

import CardBackgroundMotion from './CardBackgroundMotion';

jest.mock('../../lib/teact/teact', () => ({
  __esModule: true,
  default: { createElement: jest.fn() },
  memo: (component: unknown) => component,
  useEffect: jest.fn(),
  useRef: jest.fn(),
}));
jest.mock('../../lib/fasterdom/fasterdom', () => ({
  requestMeasure: (callback: NoneToVoidFunction) => callback(),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
}));
jest.mock('../../hooks/useMediaQuery', () => ({ useMediaQuery: () => false }));
jest.mock('../../util/cardSvgLayers', () => ({ loadCardArtworkLayers: jest.fn() }));
jest.mock('../../util/cardBackgroundMotion', () => ({
  ...jest.requireActual('../../util/cardBackgroundMotion'),
  createCardMotionRenderer: jest.fn(),
  getCardMotionSeed: () => 0,
}));

it('keeps the wave at its previous phase after an offscreen pause', async () => {
  const canvas = document.createElement('canvas');
  const image = document.createElement('img');
  Object.defineProperty(image, 'naturalWidth', { value: 100 });
  jest.mocked(useRef).mockReturnValue({ current: canvas });
  jest.mocked(loadCardArtworkLayers).mockResolvedValue(undefined);

  const draw = jest.fn();
  const destroy = jest.fn();
  jest.mocked(createCardMotionRenderer).mockReturnValue({
    draw,
    destroy,
    measure: () => ({ cssWidth: 100, cssHeight: 100 }),
    applySize: jest.fn(),
  });

  let onIntersection: IntersectionObserverCallback | undefined;
  const originalIntersectionObserver = globalThis.IntersectionObserver;
  const originalResizeObserver = globalThis.ResizeObserver;
  globalThis.IntersectionObserver = jest.fn((callback) => {
    onIntersection = callback;
    return { observe: jest.fn(), disconnect: jest.fn() };
  }) as unknown as typeof IntersectionObserver;
  globalThis.ResizeObserver = jest.fn(() => ({
    observe: jest.fn(),
    disconnect: jest.fn(),
  })) as unknown as typeof ResizeObserver;

  const pendingFrames = new Map<number, FrameRequestCallback>();
  let nextFrameId = 0;
  jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
    const id = ++nextFrameId;
    pendingFrames.set(id, callback);
    return id;
  });
  jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
    pendingFrames.delete(id);
  });

  function advance(now: number) {
    const [id, callback] = pendingFrames.entries().next().value!;
    pendingFrames.delete(id);
    callback(now);
  }

  try {
    CardBackgroundMotion({ imageRef: { current: image }, imageUrl: 'blob:card', motionKey: 'card' });
    const cleanup = jest.mocked(useEffect).mock.calls[0][0]();
    // The layers resolve before the first frame
    await Promise.resolve();
    await Promise.resolve();

    // The plain image animates as the only layer
    expect(jest.mocked(createCardMotionRenderer).mock.calls[0][1]).toEqual({
      base: image, spots: [], contrastColor: -1, contrastOpacity: 0,
    });

    advance(100);
    advance(140);
    onIntersection!([{ isIntersecting: false } as IntersectionObserverEntry], {} as IntersectionObserver);
    onIntersection!([{ isIntersecting: true } as IntersectionObserverEntry], {} as IntersectionObserver);
    advance(5000);
    advance(5040);

    const waveTimes = draw.mock.calls.map(([time]) => time);
    expect(waveTimes).toHaveLength(4);
    [0, 0.062, 0.062, 0.124].forEach((expected, index) => expect(waveTimes[index]).toBeCloseTo(expected));
    cleanup?.();
    expect(destroy).toHaveBeenCalledTimes(1);
  } finally {
    globalThis.IntersectionObserver = originalIntersectionObserver;
    globalThis.ResizeObserver = originalResizeObserver;
    jest.restoreAllMocks();
    jest.clearAllMocks();
  }
});
