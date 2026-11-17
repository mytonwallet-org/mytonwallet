import { clamp, lerp } from '../../../util/math';

/** The leverages the slider sticks to */
const LEVERAGE_PRESETS = [1, 2, 5, 10, 20, 50];

type LeverageScale = {
  /** The leverages of the slider stops: the minimum, the presets inside the range and the maximum */
  stops: number[];
  /** The slider positions of the stops, in the `[0, 1]` range */
  positions: number[];
};

/** The stops spread evenly over the track, so the low leverages get as much room as the high ones */
export function buildLeverageScale(minLeverage: number, maxLeverage: number): LeverageScale {
  const presets = LEVERAGE_PRESETS.filter((preset) => preset > minLeverage && preset < maxLeverage);
  const stops = [minLeverage, ...presets, maxLeverage];

  return {
    stops,
    positions: stops.map((_, i) => i / (stops.length - 1)),
  };
}

export function leverageToPosition({ stops, positions }: LeverageScale, leverage: number) {
  return interpolate(clamp(leverage, stops[0], stops[stops.length - 1]), stops, positions);
}

export function positionToLeverage({ stops, positions }: LeverageScale, position: number) {
  return Math.round(interpolate(clamp(position, 0, 1), positions, stops));
}

// Puts the value at the same place between the neighbouring stops of the other list
function interpolate(value: number, from: number[], to: number[]) {
  const upperIndex = from.findIndex((stop, i) => i > 0 && value <= stop);
  const upper = upperIndex === -1 ? from.length - 1 : upperIndex;
  const lower = upper - 1;
  if (from[upper] === from[lower]) return to[lower];

  return lerp(to[lower], to[upper], (value - from[lower]) / (from[upper] - from[lower]));
}
