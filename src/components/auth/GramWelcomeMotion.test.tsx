import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import GramDiamond from '../common/GramDiamond';

const mockDestroyDiamond = jest.fn();
const mockMountDiamond = jest.fn((_canvas: HTMLCanvasElement, _options: unknown) => mockDestroyDiamond);
const mockRenderLottie = jest.fn((_props: unknown) => undefined);

jest.mock('../../lib/blue-diamond/diamond', () => ({
  mountDiamond: (canvas: HTMLCanvasElement, options: unknown) => mockMountDiamond(canvas, options),
}));
jest.mock('../ui/AnimatedIconWithPreview', () => (props: unknown) => mockRenderLottie(props));

describe('Gram welcome motion', () => {
  let root: HTMLDivElement;
  let reducedMotion: MediaQueryList;
  let notifyReducedMotion: () => void;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
    reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    Object.defineProperty(reducedMotion, 'matches', { value: false, configurable: true });
    reducedMotion.addEventListener = jest.fn((_, listener) => {
      notifyReducedMotion = listener as () => void;
    });
    jest.spyOn(window, 'matchMedia').mockReturnValue(reducedMotion);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('does not initialize either animated diamond renderer with reduced motion', async () => {
    Object.defineProperty(reducedMotion, 'matches', { value: true, configurable: true });
    TeactDOM.render(<GramDiamond isOpen />, root);
    await pause(100);
    expect(mockMountDiamond).not.toHaveBeenCalled();
    expect(mockRenderLottie).not.toHaveBeenCalled();
    expect(root.querySelector('img')).not.toBeNull();
    expect(root.querySelector('canvas')).toBeNull();
  });

  it('stops the renderer when reduced motion is enabled at runtime', async () => {
    TeactDOM.render(<GramDiamond isOpen />, root);
    await pause(100);
    expect(mockMountDiamond).toHaveBeenCalledTimes(1);

    Object.defineProperty(reducedMotion, 'matches', { value: true, configurable: true });
    notifyReducedMotion();
    await pause(100);
    expect(mockDestroyDiamond).toHaveBeenCalledTimes(1);
    expect(root.querySelector('canvas')).toBeNull();
    expect(mockRenderLottie).not.toHaveBeenCalled();
  });
});
