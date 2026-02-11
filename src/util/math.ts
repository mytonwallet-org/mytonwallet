export const clamp = (num: number, min: number, max: number) => (Math.min(max, Math.max(min, num)));
export const isBetween = (num: number, min: number, max: number) => (num >= min && num <= max);
export const round = (num: number, decimals: number = 0) => Math.round(num * 10 ** decimals) / 10 ** decimals;
export const lerp = (start: number, end: number, interpolationRatio: number) => {
  return (1 - interpolationRatio) * start + interpolationRatio * end;
};

// Fractional values cause blurry text & canvas. Round to even to keep whole numbers while centering
export function roundToNearestEven(value: number) {
  return Math.round(value / 2) * 2;
}

export function getPseudoRandom(min: number, max: number, index: number) {
  const normalizedMin = Math.floor(Math.min(min, max));
  const normalizedMax = Math.floor(Math.max(min, max));
  const range = normalizedMax - normalizedMin + 1;

  let x = Math.floor(index);
  x = (x * 7 + (x % 13) * 3 + 5) % 65536;

  return normalizedMin + (x % range);
}
