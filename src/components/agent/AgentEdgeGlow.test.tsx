import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { ANIMATION_LEVEL_MAX, ANIMATION_LEVEL_MIN } from '../../config';
import {
  disableStrict, enableStrict, setHandler, setPhase,
} from '../../lib/fasterdom/stricterdom';
import { pause, waitFor } from '../../util/schedulers';

import AgentEdgeGlow from './AgentEdgeGlow';

jest.mock('../../hooks/useMediaQuery', () => ({ useMediaQuery: () => false }));

describe('AgentEdgeGlow', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    window.ResizeObserver = class {
      observe() {}

      disconnect() {}
    } as unknown as typeof ResizeObserver;
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  it('draws the glow with WebGL where it is available', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    mockGlowBox();

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
    expect(await waitFor(() => gl.drawArrays.mock.calls.length > 0, 10, 300)).toBe(true);

    expect(root.querySelector('canvas')).not.toBeNull();
    // Four strips along the edges, two triangles each
    expect(gl.drawArrays.mock.calls.at(-1)).toEqual([gl.TRIANGLES, 0, 24]);
  });

  it('reaches 32 px in along the edges and 150 px up along the bottom, behind the composer', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    mockGlowBox();

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
    expect(await waitFor(() => gl.bufferData.mock.calls.length > 0, 10, 300)).toBe(true);

    const vertices = Array.from(gl.bufferData.mock.calls.at(-1)![1] as Float32Array);
    // Each strip's left, top, right and bottom, from its two triangles
    const strips = [0, 1, 2, 3].map((index) => {
      const points = vertices.slice(index * 12, (index + 1) * 12);
      const horizontal = points.filter((_, i) => i % 2 === 0);
      const vertical = points.filter((_, i) => i % 2 === 1);
      return [Math.min(...horizontal), Math.min(...vertical), Math.max(...horizontal), Math.max(...vertical)];
    });
    // The strips run 2 px deeper than the glow, over the top, the right side, the bottom and the left side
    expect(strips).toEqual([
      [0, 0, 400, 34],
      [366, 34, 400, 650],
      [0, 650, 400, 800],
      [0, 34, 34, 650],
    ]);
  });

  it('draws in the deep blue and violet on dark and in the bright ones over light, as on iOS', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    mockGlowBox();
    document.documentElement.classList.add('theme-dark');

    try {
      TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
      expect(await waitFor(() => gl.drawArrays.mock.calls.length > 0, 10, 300)).toBe(true);
      expect(getColors(gl)).toEqual(expect.arrayContaining([[5, 109, 205], [144, 70, 203]]));
    } finally {
      document.documentElement.classList.remove('theme-dark');
    }

    gl.uniform3f.mockClear();
    expect(await waitFor(() => gl.uniform3f.mock.calls.length > 0, 10, 300)).toBe(true);
    expect(getColors(gl)).toEqual(expect.arrayContaining([[50, 158, 255], [190, 118, 253]]));
  });

  it('releases its WebGL context as the glow goes away', async () => {
    const gl = createFakeWebGl();
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockReturnValue(gl as unknown as RenderingContext);

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
    expect(await waitFor(() => gl.createProgram.mock.calls.length > 0, 10, 300)).toBe(true);

    expect(getContext).toHaveBeenCalledWith('webgl', expect.objectContaining({ failIfMajorPerformanceCaveat: true }));
    expect(gl.loseContext).not.toHaveBeenCalled();

    TeactDOM.render(undefined, root);

    expect(gl.deleteProgram).toHaveBeenCalled();
    expect(gl.loseContext).toHaveBeenCalledTimes(1);
  });

  it('draws the glow with CSS where WebGL is not available', async () => {
    // eslint-disable-next-line no-null/no-null
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
    expect(await waitFor(() => Boolean(root.querySelector('[aria-hidden] > div')), 10, 300)).toBe(true);

    expect(root.querySelector('canvas')).toBeNull();
  });

  it('sizes its canvas as it shows and as it resizes, in the phases the DOM expects', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, top: 0, left: 0, right: 400, bottom: 800, width: 400, height: 800, toJSON: () => undefined,
    });
    let resize: NoneToVoidFunction | undefined;
    window.ResizeObserver = class {
      constructor(callback: ResizeObserverCallback) {
        resize = () => callback([], this as unknown as ResizeObserver);
      }

      observe() {}

      disconnect() {}
    } as unknown as typeof ResizeObserver;
    const errors: Error[] = [];
    disableStrict();
    setPhase('measure');
    setHandler((error) => errors.push(error));
    enableStrict();

    try {
      setPhase('mutate');
      TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MIN} />, root);
      await Promise.resolve();
      setPhase('measure');
      await pause(60);
      // The observer calls back in the measure phase
      resize!();
      await pause(20);

      expect(gl.viewport).toHaveBeenCalledTimes(2);
      expect(errors).toEqual([]);
    } finally {
      disableStrict();
      setHandler();
      setPhase('measure');
    }
  });

  it('stops its lights once animations are turned off while it shows', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, top: 0, left: 0, right: 400, bottom: 800, width: 400, height: 800, toJSON: () => undefined,
    });
    const requestFrame = jest.spyOn(window, 'requestAnimationFrame');
    const cancelFrame = jest.spyOn(window, 'cancelAnimationFrame');
    // The glow's own loop, apart from the frames the rendering asks for
    const getLoopFrameCount = () => requestFrame.mock.calls.filter(([callback]) => callback.name === 'tick').length;

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MAX} />, root);
    expect(await waitFor(() => getLoopFrameCount() > 0, 10, 300)).toBe(true);

    TeactDOM.render(<AgentEdgeGlow isActive animationLevel={ANIMATION_LEVEL_MIN} />, root);
    await pause(50);
    const loopFrameCount = getLoopFrameCount();
    await pause(100);

    expect(cancelFrame).toHaveBeenCalled();
    expect(getLoopFrameCount()).toBe(loopFrameCount);
    expect(gl.drawArrays).toHaveBeenCalled();
  });
});

function mockGlowBox() {
  jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
    x: 0, y: 0, top: 0, left: 0, right: 400, bottom: 800, width: 400, height: 800, toJSON: () => undefined,
  });
}

// The colours the glow was last drawn in, from 0 to 255
function getColors(gl: ReturnType<typeof createFakeWebGl>) {
  return gl.uniform3f.mock.calls.slice(-2).map((call) => (
    call.slice(1).map((channel: number) => Math.round(channel * 255))
  ));
}

function createFakeWebGl() {
  const loseContext = jest.fn();

  return {
    loseContext,
    // eslint-disable-next-line no-null/no-null
    getExtension: jest.fn((name: string) => (name === 'WEBGL_lose_context' ? { loseContext } : null)),
    TRIANGLES: 4,
    ARRAY_BUFFER: 0x8892,
    STATIC_DRAW: 0x88E4,
    FLOAT: 0x1406,
    COLOR_BUFFER_BIT: 0x4000,
    VERTEX_SHADER: 0x8B31,
    FRAGMENT_SHADER: 0x8B30,
    COMPILE_STATUS: 0x8B81,
    LINK_STATUS: 0x8B82,
    createShader: jest.fn(() => ({})),
    shaderSource: jest.fn(),
    compileShader: jest.fn(),
    getShaderParameter: jest.fn(() => true),
    deleteShader: jest.fn(),
    createProgram: jest.fn(() => ({})),
    attachShader: jest.fn(),
    linkProgram: jest.fn(),
    getProgramParameter: jest.fn(() => true),
    deleteProgram: jest.fn(),
    createBuffer: jest.fn(() => ({})),
    deleteBuffer: jest.fn(),
    getAttribLocation: jest.fn(() => 0),
    getUniformLocation: jest.fn(() => ({})),
    useProgram: jest.fn(),
    bindBuffer: jest.fn(),
    enableVertexAttribArray: jest.fn(),
    vertexAttribPointer: jest.fn(),
    clearColor: jest.fn(),
    viewport: jest.fn(),
    bufferData: jest.fn(),
    clear: jest.fn(),
    uniform1f: jest.fn(),
    uniform2f: jest.fn(),
    uniform3f: jest.fn(),
    drawArrays: jest.fn(),
  };
}
