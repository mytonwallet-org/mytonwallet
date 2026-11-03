import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentSpinningTopHandoff } from './helpers/agentSpinningTop';

import { pause } from '../../util/schedulers';

import AgentSpinningTop from './AgentSpinningTop';

describe('AgentSpinningTop', () => {
  let root: HTMLDivElement;
  let intersectionCallbacks: IntersectionObserverCallback[];
  const originalHidden = Object.getOwnPropertyDescriptor(document, 'hidden');

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    intersectionCallbacks = [];
    window.ResizeObserver = class {
      observe() {}

      disconnect() {}
    } as unknown as typeof ResizeObserver;
    window.IntersectionObserver = class {
      constructor(callback: IntersectionObserverCallback) {
        intersectionCallbacks.push(callback);
      }

      observe() {}

      disconnect() {}
    } as unknown as typeof IntersectionObserver;
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
    if (originalHidden) {
      Object.defineProperty(document, 'hidden', originalHidden);
    } else {
      Reflect.deleteProperty(document, 'hidden');
    }
  });

  it('draws in 3D only while on screen, and the flat mark once the context is lost', async () => {
    window.WebGL2RenderingContext = class {} as unknown as typeof WebGL2RenderingContext;
    const gl = createFakeWebGl2();
    const context2d = { clearRect: jest.fn(), drawImage: jest.fn() };
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(((type: string) => {
      if (type === 'webgl2') return gl as unknown as RenderingContext;
      // eslint-disable-next-line no-null/no-null
      return type === '2d' ? context2d as unknown as RenderingContext : null;
    }) as HTMLCanvasElement['getContext']);
    // Below the window at first
    const getRect = jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 2000, top: 2000, left: 0, right: 24, bottom: 2024, width: 24, height: 24, toJSON: () => undefined,
    });
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    TeactDOM.render(<AgentSpinningTop className="box" markClassName="wobble" />, root);
    await pause(50);

    expect(root.querySelector('svg')).toBeNull();
    const canvas = root.querySelector('.box canvas') as HTMLCanvasElement;
    expect(canvas).not.toBeNull();
    // Off screen, it draws nothing
    expect(gl.drawElements).not.toHaveBeenCalled();

    getRect.mockReturnValue({
      x: 0, y: 0, top: 0, left: 0, right: 24, bottom: 24, width: 24, height: 24, toJSON: () => undefined,
    });
    intersectionCallbacks.forEach((callback) => callback(
      [{ isIntersecting: true } as IntersectionObserverEntry], {} as IntersectionObserver,
    ));
    await pause(100);

    // The back wall, then the front wall, copied into the top's own canvas
    expect(gl.drawElements.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(context2d.drawImage).toHaveBeenCalled();
    expect(canvas.width).toBe(Math.round(24 * 1.2 * (window.devicePixelRatio || 1)));
    // Every top draws with the one context, on a canvas of its own
    const sharedCanvas = getContext.mock.contexts[getContext.mock.calls.findIndex(([type]) => type === 'webgl2')];
    expect(sharedCanvas).toBeInstanceOf(HTMLCanvasElement);
    expect(sharedCanvas).not.toBe(canvas);

    // A top that takes another's place draws as it comes, before the intersection observer tells it is in view, and
    // goes on with the other's motion
    const handoff: AgentSpinningTopHandoff = {};
    TeactDOM.render(<AgentSpinningTop handoff={handoff} />, root);
    await pause(50);
    const { elapsedSeconds } = handoff.motion!;
    expect(handoff.savedAt).toBeDefined();

    TeactDOM.render(undefined, root);
    context2d.drawImage.mockClear();
    const observerCount = intersectionCallbacks.length;
    TeactDOM.render(<AgentSpinningTop handoff={handoff} />, root);
    await pause(50);
    expect(intersectionCallbacks.length).toBe(observerCount + 1);
    expect(context2d.drawImage).toHaveBeenCalled();
    expect(handoff.motion!.elapsedSeconds).toBeGreaterThanOrEqual(elapsedSeconds);

    TeactDOM.render(<AgentSpinningTop className="box" markClassName="wobble" />, root);
    await pause(50);

    // Temporary pressure while copying a frame keeps the rendered top's shape
    const realNow = performance.now.bind(performance);
    let drawingTime = 0;
    const clock = jest.spyOn(performance, 'now').mockImplementation(() => realNow() + drawingTime);
    context2d.drawImage.mockImplementation(() => {
      drawingTime += 10;
    });
    await pause(450);
    expect(root.querySelector('canvas')).not.toBeNull();
    expect(root.querySelector('svg')).toBeNull();
    expect(drawingTime).toBeGreaterThanOrEqual(120);
    clock.mockRestore();
    context2d.drawImage.mockImplementation(() => undefined);

    sharedCanvas.dispatchEvent(new Event('webglcontextlost'));
    await pause(50);

    const mark = root.querySelector('svg')!;
    expect(mark.classList.contains('box')).toBe(true);
    expect(mark.classList.contains('wobble')).toBe(true);
    expect(root.querySelector('canvas')).toBeNull();
  });
});

function createFakeWebGl2() {
  const methods: Record<string, jest.Mock> = {};
  return new Proxy({} as Record<string, jest.Mock>, {
    get(_, property: string) {
      if (property === 'NO_ERROR') return 0;
      if (/^[A-Z0-9_]+$/.test(property)) return property.length;
      if (property === 'getError') return () => 0;
      if (property === 'getShaderParameter' || property === 'getProgramParameter') return () => true;
      methods[property] ??= jest.fn(() => ({}));
      return methods[property];
    },
  });
}
