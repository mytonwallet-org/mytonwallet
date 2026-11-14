import {
  alignAccountContent,
  captureAccountContent,
  getIsAccountContentTransitionActive,
  playAccountContentTransition,
  registerAccountContent,
} from './accountContentTransition';
import { animateShift } from './layoutChangeAnimation';

jest.mock('./layoutChangeAnimation', () => ({ animateShift: jest.fn() }));

let node: HTMLDivElement;
let unregister: NoneToVoidFunction;
let finish: NoneToVoidFunction;
const animate = jest.fn(() => ({ finished: new Promise<void>((resolve) => {
  finish = resolve;
}) }));

beforeEach(() => {
  jest.useFakeTimers();
  node = document.createElement('div');
  node.innerHTML = '<button id="wallet-title">Old wallet</button>';
  document.body.append(node);
  node.getBoundingClientRect = () => ({
    left: 10, top: 20, right: 310, bottom: 220, width: 300, height: 200,
  } as DOMRect);
  node.getClientRects = () => ([node.getBoundingClientRect()] as unknown as DOMRectList);
  HTMLElement.prototype.animate = animate as unknown as typeof HTMLElement.prototype.animate;
  HTMLElement.prototype.getAnimations = jest.fn(() => []);
  unregister = registerAccountContent(node);
});
afterEach(() => {
  unregister();
  document.body.replaceChildren();
  jest.useRealTimers();
  animate.mockClear();
  jest.mocked(animateShift).mockClear();
});

describe('a region that moves for the new account', () => {
  function moveRegion(top: number, height = 200) {
    node.getBoundingClientRect = () => ({
      left: 10, top, right: 310, bottom: top + height, width: 300, height,
    } as DOMRect);
  }

  it('moves the outgoing view along with the live region and fades it after half of the way', async () => {
    captureAccountContent();
    moveRegion(-80);
    alignAccountContent(node)!();
    const layer = document.querySelector<HTMLElement>('[data-account-crossfade]')!;

    expect(layer.style.transform).toBe('translateY(-100px)');
    expect(animateShift).toHaveBeenCalledWith(layer, 0, 100, 240);
    expect(animateShift).toHaveBeenCalledWith(node, 0, 100, 240);

    playAccountContentTransition(node);
    await jest.advanceTimersByTimeAsync(40);

    expect(animate).toHaveBeenCalledWith([{ opacity: 1 }, { opacity: 0 }], expect.objectContaining({ delay: 120 }));
  });

  it('fades the outgoing view in place when the region is empty for the new account', async () => {
    captureAccountContent();
    moveRegion(-80, 0);

    expect(alignAccountContent(node)).toBeUndefined();

    playAccountContentTransition(node);
    await jest.advanceTimersByTimeAsync(40);

    expect(animate).toHaveBeenCalledWith([{ opacity: 1 }, { opacity: 0 }], expect.objectContaining({ delay: 0 }));
  });

  it('has nothing to align without an outgoing view', () => {
    moveRegion(-80);

    expect(alignAccountContent(node)).toBeUndefined();
  });

  it('keeps an interrupted outgoing view where it is on screen', () => {
    captureAccountContent();
    document.querySelector<HTMLElement>('[data-account-crossfade]')!.getBoundingClientRect = () => ({
      left: 10, top: 60, right: 310, bottom: 260, width: 300, height: 200,
    } as DOMRect);
    captureAccountContent();
    const previous = document.querySelector('[data-account-crossfade]')!.lastElementChild as HTMLElement;

    expect(previous.style.top).toBe('40px');
    expect(previous.style.transform).toBe('none');
  });

  it('fades the outgoing view in place when the region moves beyond the screen', () => {
    captureAccountContent();
    moveRegion(5000);

    expect(alignAccountContent(node)).toBeUndefined();
  });
});

it('retains the outgoing account while the live content updates, without dimming the live view', async () => {
  captureAccountContent();
  expect(getIsAccountContentTransitionActive()).toBe(true);
  node.textContent = 'New wallet';
  playAccountContentTransition(node);
  await jest.advanceTimersByTimeAsync(40);
  const layer = document.querySelector<HTMLElement>('[data-account-crossfade]')!;
  expect(layer.textContent).toBe('Old wallet');
  expect(layer.getAttribute('aria-hidden')).toBe('true');
  expect(layer.inert).toBe(true);
  expect(layer.querySelector('[id]')).toBeNull();
  expect(node.style.opacity).toBe('');
  expect(animate).toHaveBeenCalledWith([{ opacity: 1 }, { opacity: 0 }], expect.objectContaining({ duration: 240 }));
  finish();
  await Promise.resolve();
  expect(layer.isConnected).toBe(false);
  expect(getIsAccountContentTransitionActive()).toBe(false);
  expect(node.textContent).toBe('New wallet');
});

it('cleans up a superseded transition without removing the new snapshot', async () => {
  captureAccountContent();
  playAccountContentTransition(node);
  await jest.advanceTimersByTimeAsync(40);
  const finishOld = finish;
  node.textContent = 'Second wallet';
  captureAccountContent();
  finishOld();
  await Promise.resolve();
  expect(document.querySelectorAll('[data-account-crossfade]')).toHaveLength(1);
  expect(document.querySelector('[data-account-crossfade]')!.textContent).toContain('Second wallet');
  unregister();
  expect(document.querySelector('[data-account-crossfade]')).toBeNull();
});

it('expires snapshots if an update never renders', () => {
  captureAccountContent();
  jest.runAllTimers();
  expect(document.querySelector('[data-account-crossfade]')).toBeNull();
});

it('aligns the outgoing view inside a translated and scaled fixed containing block', () => {
  const measure = jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
    left: 6, top: -30, width: 2, height: 2,
  } as DOMRect);
  captureAccountContent();
  const layer = document.querySelector<HTMLElement>('[data-account-crossfade]')!;
  // The live node is at viewport (10, 20), not at (10, 20) inside its ancestor
  expect(layer.style.left).toBe('2px');
  expect(layer.style.top).toBe('25px');
  expect(layer.style.width).toBe('150px');
  expect(layer.style.height).toBe('100px');
  measure.mockRestore();
});

it('does not replay entrance animations in the outgoing view', () => {
  const entrance = {
    effect: { getComputedTiming: () => ({ endTime: 300 }) },
    finish: jest.fn(() => {
      expect(document.querySelector('[data-account-crossfade]')).not.toBeNull();
    }),
  };
  const shimmer = { effect: { getComputedTiming: () => ({ endTime: Infinity }) }, finish: jest.fn() };

  HTMLElement.prototype.getAnimations = jest.fn(() => [entrance, shimmer] as unknown as Animation[]);
  captureAccountContent();

  expect(entrance.finish).toHaveBeenCalledTimes(1);
  expect(shimmer.finish).not.toHaveBeenCalled();
});

it('clips the outgoing view without making it a scroll container, so `sticky` tabs stay in place', () => {
  node.style.overflowX = 'visible';
  captureAccountContent();
  const layer = document.querySelector<HTMLElement>('[data-account-crossfade]')!;

  expect(layer.style.overflowY).toBe('clip');
  expect(layer.style.overflowX).toBe('visible');

  node.style.overflowX = 'hidden';
  captureAccountContent();

  expect(document.querySelector<HTMLElement>('[data-account-crossfade]')!.style.overflowX).toBe('clip');
});

it('keeps the accent color of the outgoing account', () => {
  node.style.setProperty('--color-accent', '#FF0000');
  captureAccountContent();

  const layer = document.querySelector<HTMLElement>('[data-account-crossfade]')!;

  expect(layer.style.getPropertyValue('--color-accent')).toBe('#FF0000');
});

it('measures scroll positions before attaching the snapshot and preserves nested scroll', () => {
  const scroller = node.firstElementChild!;
  Object.defineProperty(scroller, 'scrollTop', { get: () => {
    expect(document.querySelector('[data-account-crossfade]')).toBeNull();
    return 72;
  } });
  captureAccountContent();
  const copy = document.querySelector('[data-account-crossfade]')!.firstElementChild!;
  expect(copy.scrollTop).toBe(72);
});

describe('thumbnail pixels in outgoing views', () => {
  const drawImage = jest.fn();
  beforeEach(() => {
    jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(
      { drawImage } as unknown as CanvasRenderingContext2D,
    );
    const image = document.createElement('img');
    image.setAttribute('data-account-crossfade-image', '');
    image.className = 'thumbnail';
    Object.defineProperties(image, {
      complete: { value: true }, naturalWidth: { value: 300 }, naturalHeight: { value: 200 },
      clientWidth: { value: 22 }, clientHeight: { value: 14 },
    });
    image.getBoundingClientRect = () => ({
      top: 30, bottom: 44, left: 20, right: 42, width: 22, height: 14,
    } as DOMRect);
    node.append(image);
  });
  afterEach(() => {
    jest.restoreAllMocks();
    drawImage.mockClear();
  });

  it('skips a canvas without pixels', () => {
    const canvas = document.createElement('canvas');

    canvas.width = 0;
    node.append(canvas);
    captureAccountContent();

    expect(drawImage).not.toHaveBeenCalledWith(canvas, 0, 0);
    expect(document.querySelector('[data-account-crossfade]')).not.toBeNull();
  });

  it('leaves a thumbnail outside the visible area as it is', () => {
    const image = node.querySelector('img')!;

    image.getBoundingClientRect = () => ({
      top: 5000, bottom: 5014, left: 20, right: 42, width: 22, height: 14,
    } as DOMRect);
    captureAccountContent();

    expect(drawImage).not.toHaveBeenCalled();
    expect(document.querySelector('[data-account-crossfade] img')).not.toBeNull();
  });

  it('paints a loaded thumbnail before attaching its outgoing copy', () => {
    const source = node.querySelector('img')!;
    drawImage.mockImplementationOnce(() => {
      expect(document.querySelector('[data-account-crossfade]')).toBeNull();
    });
    captureAccountContent();
    const layer = document.querySelector('[data-account-crossfade]')!;
    const bitmap = layer.querySelector('canvas')!;
    expect(layer.querySelector('img')).toBeNull();
    expect(node.querySelector('img')).toBe(source);
    expect(bitmap.className).toBe('thumbnail');
    expect(bitmap.width).toBe(22 * window.devicePixelRatio);
    expect(bitmap.height).toBe(14 * window.devicePixelRatio);
    expect(drawImage).toHaveBeenCalledWith(source, 0, expect.any(Number), bitmap.width, expect.any(Number));
  });

  it('retains bitmap contents when a second account interrupts the fade', () => {
    captureAccountContent();
    const firstBitmap = document.querySelector('[data-account-crossfade] canvas')!;
    captureAccountContent();
    expect(drawImage).toHaveBeenCalledWith(firstBitmap, 0, 0);
    expect(document.querySelectorAll('[data-account-crossfade] canvas')).toHaveLength(2);
  });
});

describe('several regions', () => {
  let other: HTMLDivElement;
  let unregisterOther: NoneToVoidFunction;

  beforeEach(() => {
    other = document.createElement('div');
    other.textContent = 'Old actions';
    document.body.append(other);
    other.getBoundingClientRect = node.getBoundingClientRect;
    other.getClientRects = node.getClientRects;
    unregisterOther = registerAccountContent(other);
  });
  afterEach(() => unregisterOther());

  it('fades every region together once the slowest one is ready', async () => {
    captureAccountContent();
    const image = document.createElement('img');
    image.setAttribute('data-account-crossfade-image', '');
    image.getBoundingClientRect = () => ({
      top: 30, bottom: 70, left: 20, right: 60, width: 40, height: 40,
    } as DOMRect);
    image.decode = jest.fn(() => new Promise(() => {}));
    node.replaceChildren(image);
    playAccountContentTransition(other);
    playAccountContentTransition(node);
    await jest.advanceTimersByTimeAsync(100);

    expect(animate).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(70);

    expect(animate).toHaveBeenCalledTimes(2);
  });

  it('starts the waiting regions when a region that is not ready goes away', async () => {
    captureAccountContent();
    playAccountContentTransition(other);
    await jest.advanceTimersByTimeAsync(40);

    expect(animate).not.toHaveBeenCalled();

    unregister();
    await jest.advanceTimersByTimeAsync(40);

    expect(animate).toHaveBeenCalledTimes(1);
  });
});

it('keeps an opaque first frame and cancels a queued start on unmount', async () => {
  captureAccountContent();
  playAccountContentTransition(node);
  expect(animate).not.toHaveBeenCalled();
  await jest.advanceTimersByTimeAsync(16);
  expect(animate).not.toHaveBeenCalled();
  unregister();
  await jest.advanceTimersByTimeAsync(50);
  expect(animate).not.toHaveBeenCalled();
});

it('waits for visible incoming icons to decode, with a bounded deadline', async () => {
  captureAccountContent();
  const image = document.createElement('img');
  image.setAttribute('data-account-crossfade-image', '');
  image.getBoundingClientRect = () => ({ top: 30, bottom: 70, left: 20, right: 60, width: 40, height: 40 } as DOMRect);
  image.decode = jest.fn(() => new Promise(() => {}));
  node.replaceChildren(image);
  playAccountContentTransition(node);
  await jest.advanceTimersByTimeAsync(119);
  expect(animate).not.toHaveBeenCalled();
  expect(document.querySelector('[data-account-crossfade]')).not.toBeNull();
  await jest.advanceTimersByTimeAsync(50);
  expect(animate).toHaveBeenCalledTimes(1);
  finish();
  await Promise.resolve();
  expect(document.querySelector('[data-account-crossfade]')).toBeNull();
});
