import type { VirtualElement } from '../../lib/teact/teact';
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

  it('stands a large top on the ground, and spins it up while the Agent thinks', async () => {
    const { gl, renderTop, unmountTop } = await prepareFreshTop();

    renderTop({ className: 'box', shouldShowGround: true });
    await showTop();

    // Its canvas reaches below its box for the shadow and the reflection, and the ground draws under the top
    const canvas = root.querySelector('.box canvas') as HTMLCanvasElement;
    expect(canvas.height).toBeGreaterThan(canvas.width);
    expect(gl.drawArrays).toHaveBeenCalledWith(expect.anything(), 0, 4);
    // The reflection's walls, then the top's
    const reflectionOpacities = gl.uniform4f.mock.calls.slice(-2).map((call) => call[4]);
    expect(reflectionOpacities[0]).toBeGreaterThan(0);
    expect(reflectionOpacities[1]).toBe(0);
    const getStreaks = () => gl.uniform4f.mock.calls.at(-1)![3] as number;
    expect(getStreaks()).toBe(0);

    renderTop({ className: 'box', shouldShowGround: true, agentState: 'thinking' });
    await pause(900);

    // Thinking spins it so fast that its surface smears into rings
    expect(getStreaks()).toBeGreaterThan(0);

    renderTop({ className: 'box', shouldShowGround: true });
    await pause(2500);

    expect(getStreaks()).toBe(0);
    unmountTop();
  });

  it('shrinks a top a Stop grew as soon as the next state comes', async () => {
    const { renderTop, unmountTop } = await prepareFreshTop();
    // The grown top draws on a canvas of its own over the window
    const getLiftedCanvas = () => document.body.querySelector(':scope > canvas');

    renderTop({ isTouchInteractive: true, agentState: 'thinking' });
    await showTop();
    expect(getLiftedCanvas()).toBeNull();

    renderTop({ isTouchInteractive: true, agentState: 'stopped' });
    await pause(100);
    expect(getLiftedCanvas()).not.toBeNull();

    // A question sent right after the Stop: the top springs back into its place, which takes under 2 s
    renderTop({ isTouchInteractive: true, agentState: 'thinking' });
    await pause(2300);

    expect(getLiftedCanvas()).toBeNull();
    unmountTop();
  });

  // A lost context fails the renderer for good, so the top comes from modules of its own, with a global of their own
  async function prepareFreshTop() {
    jest.resetModules();
    await import('../../../tests/initGlobal');
    const { default: FreshReact } = await import('../../lib/teact/teact');
    const { default: FreshTeactDOM } = await import('../../lib/teact/teact-dom');
    const { default: FreshTop } = await import('./AgentSpinningTop');
    window.WebGL2RenderingContext = class {} as unknown as typeof WebGL2RenderingContext;
    const gl = createFakeWebGl2();
    const context2d = { clearRect: jest.fn(), drawImage: jest.fn() };
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(((type: string) => {
      if (type === 'webgl2') return gl as unknown as RenderingContext;
      // eslint-disable-next-line no-null/no-null
      return type === '2d' ? context2d as unknown as RenderingContext : null;
    }) as HTMLCanvasElement['getContext']);
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, top: 0, left: 0, right: 100, bottom: 100, width: 100, height: 100, toJSON: () => undefined,
    });
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });

    return {
      gl,
      renderTop: (props: Parameters<typeof FreshTop>[0]) => FreshTeactDOM.render(
        FreshReact.createElement(FreshTop, props) as VirtualElement, root,
      ),
      unmountTop: () => FreshTeactDOM.render(undefined, root),
    };
  }

  // The first frame waits for the intersection observer to tell the top is in view
  async function showTop() {
    await pause(50);
    intersectionCallbacks.forEach((callback) => callback(
      [{ isIntersecting: true } as IntersectionObserverEntry], {} as IntersectionObserver,
    ));
    await pause(100);
  }
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
