import {
  cacheWhileConnected, getBezierProgress, getShare, getTelegramProgress, interpolateRect,
} from './agentMotion';

// Telegram's curve, `cubic-bezier(0.38, 0.7, 0.125, 1)`, drawn point by point
const CURVE_POINTS = Array.from({ length: 20_001 }, (_, index) => {
  const time = index / 20_000;
  const inverse = 1 - time;
  return {
    x: 3 * inverse * inverse * time * 0.38 + 3 * inverse * time * time * 0.125 + time ** 3,
    y: 3 * inverse * inverse * time * 0.7 + 3 * inverse * time * time + time ** 3,
  };
});

describe('getTelegramProgress', () => {
  it('follows Telegram\'s curve from rest to rest, as the browser plays it', () => {
    expect(getTelegramProgress(0)).toBe(0);
    expect(getTelegramProgress(1)).toBe(1);
    expect(getTelegramProgress(-0.2)).toBe(0);
    expect(getTelegramProgress(1.2)).toBe(1);

    let previous = 0;
    for (let index = 1; index < 100; index++) {
      const fraction = index / 100;
      const progress = getTelegramProgress(fraction);
      const point = CURVE_POINTS.reduce((nearest, candidate) => (
        Math.abs(candidate.x - fraction) < Math.abs(nearest.x - fraction) ? candidate : nearest
      ));
      expect(progress).toBeCloseTo(point.y, 3);
      expect(progress).toBeGreaterThan(previous);
      previous = progress;
    }
    // Most of the way is gone early, as the curve's ease-out has it
    expect(getTelegramProgress(0.3)).toBeGreaterThan(0.6);
  });
});

describe('getBezierProgress', () => {
  it('plays any curve as the browser does, the straight one as it goes', () => {
    expect(getBezierProgress({
      x1: 0, y1: 0, x2: 1, y2: 1,
    }, 0.37)).toBeCloseTo(0.37, 6);
    // CSS's `ease-out` is halfway at a third of its time
    const easeOut = {
      x1: 0, y1: 0, x2: 0.58, y2: 1,
    };
    expect(getBezierProgress(easeOut, 0.3425)).toBeCloseTo(0.5, 3);
    expect(getBezierProgress(easeOut, 0.5)).toBeCloseTo(0.6846, 3);
    expect(getBezierProgress(easeOut, 0)).toBe(0);
    expect(getBezierProgress(easeOut, 1)).toBe(1);
  });
});

describe('getShare', () => {
  it('tells how far a value is through a range, from 0 before it to 1 after it', () => {
    expect(getShare(0.1, 0.15, 0.6)).toBe(0);
    expect(getShare(0.375, 0.15, 0.6)).toBeCloseTo(0.5);
    expect(getShare(0.9, 0.15, 0.6)).toBe(1);
  });
});

describe('interpolateRect', () => {
  it('moves and resizes a rectangle part of the way to another', () => {
    expect(interpolateRect(
      {
        left: 0, top: 100, width: 100, height: 40,
      },
      {
        left: 200, top: 0, width: 300, height: 80,
      },
      0.25,
    )).toEqual({
      left: 50, top: 75, width: 150, height: 50,
    });
  });
});

describe('cacheWhileConnected', () => {
  it('looks for its element again only once the one it found has left the document', () => {
    const first = document.createElement('div');
    const second = document.createElement('div');
    document.body.append(first, second);
    let shown = first;
    const find = jest.fn(() => shown);
    const findShown = cacheWhileConnected(find);

    expect(findShown()).toBe(first);
    expect(findShown()).toBe(first);
    expect(find).toHaveBeenCalledTimes(1);

    // The list renders it anew
    first.remove();
    shown = second;
    expect(findShown()).toBe(second);
    expect(find).toHaveBeenCalledTimes(2);

    second.remove();
  });
});
