import { mountDiamond } from './diamond';

const mockDraw = jest.fn();
jest.mock('./scene', () => ({
  createDiamondScene: () => Promise.resolve({ draw: mockDraw }),
  getFrameTime: (now: number, previous?: number) => previous === undefined ? 0 : (now - previous) / 1000,
  TURN_DURATION: 4,
}));

describe('existing shared diamond input recovery', () => {
  let canvas: HTMLCanvasElement;
  let destroy: () => void;
  beforeEach(async () => {
    jest.useFakeTimers();
    mockDraw.mockClear();
    jest.spyOn(window, 'IntersectionObserver').mockImplementation((callback) => ({
      observe: () => callback([{ isIntersecting: true }] as IntersectionObserverEntry[], {} as IntersectionObserver),
      disconnect: jest.fn(), unobserve: jest.fn(), takeRecords: jest.fn(),
      root: document, rootMargin: '', thresholds: [],
    }));
    canvas = document.createElement('canvas');
    canvas.setPointerCapture = jest.fn();
    jest.spyOn(canvas, 'getContext')
      .mockReturnValue({ getExtension: () => undefined } as unknown as WebGL2RenderingContext);
    destroy = mountDiamond(canvas);
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
  });
  afterEach(() => {
    destroy();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });
  function dispatchPointerEvent(type: string, buttons = 0, x = 0, y = 0) {
    const event = new MouseEvent(type, { button: 0, buttons });
    Object.defineProperties(event, { offsetX: { value: x }, offsetY: { value: y } });
    canvas.dispatchEvent(event);
  }
  function getYaw() {
    return mockDraw.mock.calls.at(-1)[4];
  }
  it('uses the current canvas size after a display-density change', () => {
    canvas.width = 184;
    canvas.height = 184;
    jest.advanceTimersByTime(32);
    expect(mockDraw.mock.calls.at(-1)[1].size).toBe(184);
    canvas.width = 368;
    canvas.height = 368;
    jest.advanceTimersByTime(32);
    expect(mockDraw.mock.calls.at(-1)[1].size).toBe(368);
  });
  it.each(['pointerup', 'pointercancel', 'lostpointercapture', 'blur'])('recovers after %s', (event) => {
    dispatchPointerEvent('pointerdown', 1);
    jest.advanceTimersByTime(100);
    const heldYaw = getYaw();
    if (event === 'blur') window.dispatchEvent(new Event('blur'));
    else dispatchPointerEvent(event);
    jest.advanceTimersByTime(2000);
    expect(getYaw()).not.toBe(heldYaw);
  });

  it('makes three horizontal turns on a welcome tap from the current angle', async () => {
    destroy();
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true, hoverSpeed: 2 });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent('pointerdown', 1, 0, 60);
    const fromYaw = getYaw();
    jest.advanceTimersByTime(100);
    expect(getYaw()).toBe(fromYaw);
    dispatchPointerEvent('pointerup', 0, 0, 60);
    jest.advanceTimersByTime(900);
    expect(getYaw() - fromYaw).toBeGreaterThan(16.2);
    expect(getYaw() - fromYaw).toBeLessThan(16.8);
    expect(mockDraw.mock.calls.at(-1)[5]).toBe(0);
    jest.advanceTimersByTime(900);
    expect(Math.abs(getYaw() - fromYaw - 6 * Math.PI)).toBeLessThan(0.06);
    expect(mockDraw.mock.calls.at(-1)[5]).toBe(0);
  });

  it('extends a repeated tap from the current angle and angular velocity', async () => {
    destroy();
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent('pointerdown', 1);
    dispatchPointerEvent('pointerup');
    jest.advanceTimersByTime(900);
    const before = getYaw();
    jest.advanceTimersByTime(16);
    const atPress = getYaw();
    const previousTravel = atPress - before;
    dispatchPointerEvent('pointerdown', 1);
    jest.advanceTimersByTime(80);
    expect(getYaw()).toBe(atPress);
    dispatchPointerEvent('pointerup');
    jest.advanceTimersByTime(16);
    expect(getYaw() - atPress).toBeGreaterThan(previousTravel * 0.85);
    expect(getYaw() - atPress).toBeLessThan(previousTravel * 1.15);
    jest.advanceTimersByTime(1784);
    expect(Math.abs(getYaw() - atPress - 6 * Math.PI)).toBeLessThan(0.06);
  });

  it('grows immediately but does not spin during or after a long hold', async () => {
    destroy();
    Object.defineProperty(canvas, 'clientWidth', { value: 184 });
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true, maxGrow: 1.15 });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    const restingPixels = canvas.width;
    const fromYaw = getYaw();
    dispatchPointerEvent('pointerdown', 1);
    jest.advanceTimersByTime(100);
    expect(Number(canvas.style.transform.match(/[\d.]+/)![0])).toBeGreaterThan(1.02);
    expect(getYaw()).toBe(fromYaw);
    jest.advanceTimersByTime(600);
    const scale = Number(canvas.style.transform.match(/[\d.]+/)![0]);
    expect(scale).toBeGreaterThan(1.14);
    expect(scale).toBeLessThanOrEqual(1.15);
    expect(canvas.width).toBe(restingPixels);
    expect(getYaw()).toBe(fromYaw);
    dispatchPointerEvent('pointerup');
    jest.advanceTimersByTime(1100);
    expect(Math.abs(getYaw())).toBeLessThan(Math.PI);
    jest.advanceTimersByTime(700);
    expect(canvas.style.transform).toBe('scale(1)');
  });

  it('takes manual control on press, even before crossing the tap movement tolerance', async () => {
    destroy();
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent('pointerdown', 1);
    const fromYaw = getYaw();
    dispatchPointerEvent('pointermove', 1, 4, 4);
    jest.advanceTimersByTime(32);
    expect(getYaw()).toBeGreaterThan(fromYaw);
    expect(mockDraw.mock.calls.at(-1)[5]).toBeGreaterThan(0);
    dispatchPointerEvent('pointermove', 1, 30, 30);
    jest.advanceTimersByTime(32);
    dispatchPointerEvent('pointerup', 0, 30, 30);
    jest.advanceTimersByTime(900);
    expect(Math.abs(getYaw())).toBeLessThan(Math.PI);
  });

  it('interrupts automatic turns on press and does not rewind those turns after holding', async () => {
    destroy();
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent('pointerdown', 1);
    dispatchPointerEvent('pointerup');
    jest.advanceTimersByTime(900);
    expect(getYaw()).toBeGreaterThan(4 * Math.PI);
    dispatchPointerEvent('pointerdown', 1);
    const heldYaw = getYaw();
    jest.advanceTimersByTime(700);
    expect(getYaw()).toBe(heldYaw);
    dispatchPointerEvent('pointerup');
    jest.advanceTimersByTime(32);
    expect(Math.abs(getYaw())).toBeLessThan(Math.PI);
    jest.advanceTimersByTime(1800);
    expect(Math.abs(getYaw())).toBeLessThan(Math.PI);
  });

  it('does not start a full turn for a cancelled welcome press', async () => {
    destroy();
    destroy = mountDiamond(canvas, { shouldRotateOnTap: true });
    await Promise.resolve();
    jest.advanceTimersByTime(1000);
    dispatchPointerEvent('pointerdown', 1);
    dispatchPointerEvent('pointercancel');
    jest.advanceTimersByTime(900);
    expect(Math.abs(getYaw())).toBeLessThan(Math.PI);
  });
});
