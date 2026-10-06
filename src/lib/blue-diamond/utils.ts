export const clamp = (num: number, min: number, max: number) => Math.min(max, Math.max(min, num));

export const lerp = (start: number, end: number, ratio: number) => (1 - ratio) * start + ratio * end;

export const easeOutQuint = (t: number) => 1 + (--t) * t ** 4;

export function rafPromise() {
  return new Promise<void>((resolve) => {
    requestAnimationFrame(() => resolve());
  });
}
