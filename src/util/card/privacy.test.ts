import { createDust, createPrivacyField, createRepulsion, sourceInkBounds, transitionFootprint } from './privacy';

// These tests check whether the canvas or the DOM shows the text at the start and end of a transition.
// The drawn pixels need a real canvas and fonts, so they are checked manually in the browser.
function setup(sourceWidth = 224) {
  const contexts = new Map<HTMLCanvasElement, { isPainted: boolean; ctx: CanvasRenderingContext2D }>();

  jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(function (this: HTMLCanvasElement) {
    if (!contexts.has(this)) {
      const entry = { isPainted: false, ctx: {} as CanvasRenderingContext2D };

      Object.assign(entry.ctx, {
        setTransform: jest.fn(),
        clearRect: () => {
          entry.isPainted = false;
        },
        drawImage: () => {
          entry.isPainted = true;
        },
        fill: () => {
          entry.isPainted = true;
        },
        fillRect: jest.fn(),
        createRadialGradient: () => ({ addColorStop: jest.fn() }),
        getImageData: () => ({ data: new Uint8ClampedArray(this.width * this.height * 4).fill(255) }),
      });

      contexts.set(this, entry);
    }

    return contexts.get(this)!.ctx;
  } as any);

  const canvas = document.createElement('canvas');
  const target = document.createElement('span');
  const image = document.createElement('canvas');
  image.width = sourceWidth * 2;
  image.height = 48 * 2;

  const snapshot = jest.fn(() => image);
  const field = createPrivacyField(canvas, target, snapshot, sourceWidth, 48, ['white', 'white'], {
    x: (sourceWidth - 224) / 2,
    y: 4,
    width: 224,
    height: 40,
  });
  const advance = (seconds: number) => {
    for (let i = 0; i < Math.ceil(seconds * 60); i++) field.advance(1 / 60);
  };

  return { field, target, snapshot, advance, overlay: contexts.get(canvas)! };
}

beforeEach(() => {
  Object.assign(globalThis, {
    Path2D: class {
      moveTo() {}
      arc() {}
    },
  });
});

afterEach(() => jest.restoreAllMocks());

it('removes every snapshot pixel before revealing the live amount, including subsequent idle frames', () => {
  const { field, target, advance, overlay } = setup();
  field.toggle(true, [112, 24]);
  advance(0.8);
  expect(target.style.visibility).toBe('hidden');
  expect(overlay.isPainted).toBe(true);
  field.toggle(false, [112, 24]);
  advance(0.7);
  expect(target.style.visibility).toBe('visible');
  expect(field.isTransitioning).toBe(false);
  expect(overlay.isPainted).toBe(false);
  advance(0.5);
  expect(overlay.isPainted).toBe(false);
});

it('reverses one transition without capturing or layering another copy of the amount', () => {
  const { field, snapshot, advance, overlay, target } = setup();
  field.toggle(true, [112, 24]);
  advance(0.2);

  const progress = field.progress;
  field.toggle(false, [112, 24]);
  expect(field.progress).toBe(progress);
  expect(snapshot).toHaveBeenCalledTimes(1);
  advance(0.7);
  expect(target.style.visibility).toBe('visible');
  expect(overlay.isPainted).toBe(false);
});

it('clears an outgoing snapshot immediately when animation policy changes to instant', () => {
  const { field, target, advance, overlay } = setup();
  field.toggle(true, [112, 24]);
  advance(0.2);
  expect(overlay.isPainted).toBe(true);
  field.toggle(false, [112, 24], true);
  expect(overlay.isPainted).toBe(false);
  expect(target.style.visibility).toBe('visible');
});

it('goes to the requested state at once when the snapshot fails', () => {
  const { field, target, snapshot, overlay } = setup();
  snapshot.mockImplementation(() => {
    throw new TypeError('ctx.roundRect is not a function');
  });

  expect(() => field.toggle(true, [112, 24])).toThrow(TypeError);
  expect(target.style.visibility).toBe('hidden');
  expect(overlay.isPainted).toBe(true);

  expect(() => field.toggle(false, [112, 24])).toThrow(TypeError);
  expect(target.style.visibility).toBe('visible');
  expect(overlay.isPainted).toBe(false);
  expect(field.isTransitioning).toBe(false);
});

it('reserves the same particle count for short and long amounts', () => {
  const short = setup(60);
  const long = setup(300);
  expect(short.field.dust.samples.length).toBe(long.field.dust.samples.length);
});

it('keeps mouse repulsion local and softer while preserving touch reach', () => {
  const mouse = createRepulsion(0.4);
  const touch = createRepulsion(0.4);

  for (let i = 0; i < 60; i++) {
    mouse.advance([45, 0], [0, 0], [1, 0], 1 / 60, 'mouse');
    touch.advance([45, 0], [0, 0], [1, 0], 1 / 60, 'touch');
  }

  expect(Math.hypot(...mouse.offset)).toBe(0);
  expect(Math.hypot(...touch.offset)).toBeGreaterThan(0.1);

  for (let i = 0; i < 60; i++) {
    mouse.advance([0, 0], [0, 0], [1, 0], 1 / 60, 'mouse');
    touch.advance([0, 0], [0, 0], [1, 0], 1 / 60, 'touch');
  }

  expect(Math.hypot(...mouse.offset) / Math.hypot(...touch.offset)).toBeCloseTo(14 / 40, 4);
});

it('paints an offscreen hidden amount immediately without waiting for activation or RAF', () => {
  const { field, target, overlay, snapshot } = setup();
  field.toggle(true, [112, 24], true);
  expect(target.style.visibility).toBe('hidden');
  expect(overlay.isPainted).toBe(true);
  expect(field.isTransitioning).toBe(false);
  expect(snapshot).not.toHaveBeenCalled();

  const time = field.time;
  field.advance(1, undefined, true);
  expect(field.time).toBe(time);
  expect(overlay.isPainted).toBe(true);
  field.toggle(false, [112, 24], true);
  expect(target.style.visibility).toBe('visible');
  expect(overlay.isPainted).toBe(false);
});

it('measures actual source ink rather than the layout width', () => {
  setup();

  const image = document.createElement('canvas');
  image.width = 200;
  image.height = 20;

  const pixels = new Uint8ClampedArray(200 * 20 * 4);
  pixels[(5 * 200 + 84) * 4 + 3] = 255;
  pixels[(10 * 200 + 115) * 4 + 3] = 255;
  jest.spyOn(image.getContext('2d')!, 'getImageData').mockReturnValue({ data: pixels } as ImageData);
  expect(sourceInkBounds(image, 100)).toEqual({ x: 42, width: 16 });
});

it('expands short ink smoothly to the fixed field and retraces the same path on reversal', () => {
  const source = { x: 42, width: 16 };
  const widths = Array.from({ length: 61 }, (_, i) => transitionFootprint(source, -62, 224, i / 60 * 0.75).width);
  expect(widths[0]).toBe(16);
  expect(widths.at(-1)).toBe(224);

  for (let i = 1; i < widths.length; i++) {
    expect(widths[i]).toBeGreaterThanOrEqual(widths[i - 1]);
    expect(widths[i] - widths[i - 1]).toBeLessThan(7);
  }

  expect(transitionFootprint(source, -62, 224, 0.75)).toEqual(transitionFootprint(undefined, -62, 224, 1));

  const middle = transitionFootprint(source, -62, 224, 0.3);
  transitionFootprint(source, -62, 224, 0.6);
  expect(transitionFootprint(source, -62, 224, 0.3)).toEqual(middle);
});

it('skips settled dynamics while retaining live drift, twinkle and circular dot sizes', () => {
  const dust = createDust(224, 40);
  dust.advance(0);

  const before = dust.samples.map((s) => ({ ...s }));
  for (let i = 0; i < 60; i++) dust.advance(1 / 60);
  expect(dust.dynamicsSteps).toBe(0);
  expect(dust.samples.map((s) => s.diameter)).toEqual(before.map((s) => s.diameter));
  expect(dust.samples.map((s) => s.x)).not.toEqual(before.map((s) => s.x));
  dust.advance(1 / 60, [112, 20]);
  expect(dust.dynamicsSteps).toBeGreaterThan(0);
  for (let i = 0; i < 300; i++) dust.advance(1 / 60);

  const settled = dust.dynamicsSteps;
  for (let i = 0; i < 60; i++) dust.advance(1 / 60);
  expect(dust.dynamicsSteps).toBe(settled);
});

it('retains particle identity and current positions through geometry changes', () => {
  const dust = createDust(224, 40);
  dust.advance(0.25);

  const old = dust.samples.map((s) => ({ ...s }));
  const identities = [...dust.samples];
  dust.resize(180, 36);
  dust.advance(0);

  old.forEach((s, i) => {
    expect(dust.samples[i]).toBe(identities[i]);
    expect(dust.samples[i].x - 90).toBeCloseTo(s.x - 112);
    expect(dust.samples[i].y - 18).toBeCloseTo(s.y - 20);
    expect(dust.samples[i].diameter).toBe(s.diameter);
  });

  for (let i = 0; i < 180; i++) dust.advance(1 / 60);
  expect(dust.samples.length).toBe(Math.floor(180 * 36 * 0.28 * 0.75));
});
