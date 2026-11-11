import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import AgentMark from './AgentMark';

// Points sampled along each curve of the outline
const CURVE_SAMPLES = 64;

describe('AgentMark', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('draws the resting top\'s silhouette in the middle of its box', () => {
    TeactDOM.render(<AgentMark />, root);
    const svg = root.querySelector('svg')!;
    const outline = measureOutline(svg.querySelector('path')!.getAttribute('d')!);

    // The silhouette of the top as the 3D renderer draws it at rest, in the 48 × 48 design box
    expect(outline.left).toBeCloseTo(5.62, 1);
    expect(outline.right).toBeCloseTo(40.45, 1);
    expect(outline.top).toBeCloseTo(5.40, 1);
    expect(outline.bottom).toBeCloseTo(42.93, 1);
    const [x, y, width, height] = svg.getAttribute('viewBox')!.split(' ').map(Number);
    expect([width, height]).toEqual([48, 48]);
    expect(x + width / 2).toBeCloseTo((outline.left + outline.right) / 2, 1);
    expect(y + height / 2).toBeCloseTo((outline.top + outline.bottom) / 2, 1);
  });
});

// The bounds of an outline made of a move, cubic curves and a close, all in absolute coordinates
function measureOutline(d: string) {
  const commands = d.match(/[MCZ][^MCZ]*/gu)!;
  const bounds = {
    left: Infinity, right: -Infinity, top: Infinity, bottom: -Infinity,
  };
  let current = [0, 0];
  commands.forEach((command) => {
    const values = command.slice(1).trim().split(/[\s,]+/u).filter(Boolean).map(Number);
    if (command[0] === 'M') {
      current = values;
      include(current);
    } else if (command[0] === 'C') {
      const [x1, y1, x2, y2, x, y] = values;
      for (let step = 1; step <= CURVE_SAMPLES; step++) {
        const t = step / CURVE_SAMPLES;
        const u = 1 - t;
        include([
          u * u * u * current[0] + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x,
          u * u * u * current[1] + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y,
        ]);
      }
      current = [x, y];
    }
  });
  return bounds;

  function include([x, y]: number[]) {
    bounds.left = Math.min(bounds.left, x);
    bounds.right = Math.max(bounds.right, x);
    bounds.top = Math.min(bounds.top, y);
    bounds.bottom = Math.max(bounds.bottom, y);
  }
}
