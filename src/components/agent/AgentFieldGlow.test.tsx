import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentFieldGlow from './AgentFieldGlow';

jest.mock('../../hooks/useMediaQuery', () => ({ useMediaQuery: () => false }));

// The fake context names each uniform's location after it
const MARGIN_LOCATION = 'u_margin';
const TINT_LOCATION = 'u_tint';

describe('AgentFieldGlow', () => {
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

  it('draws the lights and the rim with WebGL over the field and beyond it, in the accent', async () => {
    const gl = createFakeWebGl();
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(gl as unknown as RenderingContext);
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: HTMLElement) {
      // The canvas reaches 28 px beyond the 300 by 44 px field on every side
      const isCanvas = this.tagName === 'CANVAS';
      const width = isCanvas ? 356 : 300;
      const height = isCanvas ? 100 : 44;
      return {
        x: 0, y: 0, top: 0, left: 0, right: width, bottom: height, width, height, toJSON: () => undefined,
      };
    });
    // The canvas takes the accent as its colour
    const style = document.createElement('style');
    style.textContent = 'canvas { color: rgb(0, 136, 204); }';
    document.head.appendChild(style);

    TeactDOM.render(<AgentFieldGlow isActive />, root);
    await pause(50);

    const canvas = root.querySelector('canvas')!;
    expect(canvas.width).toBe(Math.ceil(356 * Math.min(2, window.devicePixelRatio || 1)));
    expect(gl.uniform1f).toHaveBeenCalledWith(MARGIN_LOCATION, 28);
    expect(gl.uniform3f).toHaveBeenLastCalledWith(TINT_LOCATION, 0, 136 / 255, 204 / 255);
    // Two triangles over the whole canvas
    expect(gl.drawArrays.mock.calls.at(-1)).toEqual([gl.TRIANGLES, 0, 6]);
    style.remove();
  });

  it('releases its WebGL context as the glow goes away', async () => {
    const gl = createFakeWebGl();
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockReturnValue(gl as unknown as RenderingContext);

    TeactDOM.render(<AgentFieldGlow isActive />, root);
    await pause(50);

    expect(getContext).toHaveBeenCalledWith('webgl', expect.objectContaining({ failIfMajorPerformanceCaveat: true }));
    expect(gl.loseContext).not.toHaveBeenCalled();

    TeactDOM.render(undefined, root);

    expect(gl.deleteProgram).toHaveBeenCalled();
    expect(gl.loseContext).toHaveBeenCalledTimes(1);
  });

  it('draws the lights with CSS where WebGL is not available', async () => {
    // eslint-disable-next-line no-null/no-null
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);

    TeactDOM.render(<AgentFieldGlow isActive />, root);
    await pause(50);

    expect(root.querySelector('canvas')).toBeNull();
    expect(root.querySelector('[aria-hidden] > span')).not.toBeNull();
  });
});

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
    getUniformLocation: jest.fn((program: unknown, name: string) => name),
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
