import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

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
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, top: 0, left: 0, right: 400, bottom: 800, width: 400, height: 800, toJSON: () => undefined,
    });

    TeactDOM.render(<AgentEdgeGlow isActive />, root);
    await pause(50);

    expect(root.querySelector('canvas')).not.toBeNull();
    expect(gl.drawArrays).toHaveBeenCalled();
    // Four strips along the edges, two triangles each
    expect(gl.drawArrays.mock.calls.at(-1)).toEqual([gl.TRIANGLES, 0, 24]);
  });

  it('releases its WebGL context as the glow goes away', async () => {
    const gl = createFakeWebGl();
    const getContext = jest.spyOn(HTMLCanvasElement.prototype, 'getContext')
      .mockReturnValue(gl as unknown as RenderingContext);

    TeactDOM.render(<AgentEdgeGlow isActive />, root);
    await pause(50);

    expect(getContext).toHaveBeenCalledWith('webgl', expect.objectContaining({ failIfMajorPerformanceCaveat: true }));
    expect(gl.loseContext).not.toHaveBeenCalled();

    TeactDOM.render(undefined, root);

    expect(gl.deleteProgram).toHaveBeenCalled();
    expect(gl.loseContext).toHaveBeenCalledTimes(1);
  });

  it('turns a conic gradient under the edges where WebGL is not available', async () => {
    // eslint-disable-next-line no-null/no-null
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);

    TeactDOM.render(<AgentEdgeGlow isActive />, root);
    await pause(50);

    expect(root.querySelector('canvas')).toBeNull();
    expect(root.querySelector('[aria-hidden] > div')).not.toBeNull();
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
    drawArrays: jest.fn(),
  };
}
