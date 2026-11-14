import type { RgbaColor } from '../../../util/colors';
import type { AgentGlowColor, AgentGlowColors } from './agentGlowPalette';
import type { BezierCurve } from './agentMotion';

import { parseCssColor } from '../../../util/colors';
import { getAgentTextColors } from './agentGlowPalette';
import { getBezierProgress } from './agentMotion';

// How a streamed character comes in, as on iOS: transparent, out of a glow in the Agent's blue, sharp within
// `SHARPEN_DURATION`, in the Agent's blue, which turns violet by the middle of its turn into the text's own colour
// within `COLOR_DURATION`, so the fresh end of a line runs from blue to violet
const SHARPEN_DURATION = 0.15;
const COLOR_DURATION = 0.5;
export const STREAMED_CHARACTER_DURATION_MS = (SHARPEN_DURATION + COLOR_DURATION) * 1000;
// The glow lasts as long as the character sharpens
export const STREAMED_CHARACTER_GLOW_DURATION_MS = SHARPEN_DURATION * 1000;
const INITIAL_OPACITY = 0.15;
const INITIAL_GLOW_OPACITY = 0.9;
// The glow's blur as it starts, in CSS pixels: iOS's shadow radius of 3 pt
const INITIAL_GLOW_BLUR = 6;
// The settling is sampled this often, in seconds, as iOS samples its colours
const SAMPLE_INTERVAL = 0.025;
export const STREAMED_CHARACTER_SAMPLE_INTERVAL_MS = SAMPLE_INTERVAL * 1000;
// iOS's ease-out, which the character's opacity and its glow take as it sharpens
const EASE_OUT: BezierCurve = {
  x1: 0, y1: 0, x2: 0.58, y2: 1,
};

const colorsByKey = new Map<string, string[] | undefined>();
const glowKeyframesByKey = new Map<string, Keyframe[]>();
const copyKeyframesByKey = new Map<string, Keyframe[] | undefined>();

/**
 * The keyframes of a copy of a streamed character in `textColor` over `STREAMED_CHARACTER_DURATION_MS` that shows the
 * whole character, in its colours (`getStreamedCharacterColors`) and with its glow, over a cover that hides the text,
 * where the text cannot take its colours itself. A colour that cannot be read has none.
 */
export function getStreamedCharacterCopyKeyframes(textColor: string, isDark: boolean) {
  const key = `${isDark ? 'dark' : 'light'}:${textColor}`;
  if (!copyKeyframesByKey.has(key)) {
    const colors = getStreamedCharacterColors(textColor, isDark);
    const glowKeyframes = getStreamedCharacterGlowKeyframes(textColor, isDark);
    copyKeyframesByKey.set(
      key,
      colors && glowKeyframes.map((keyframe, index) => ({ ...keyframe, color: colors[index] })),
    );
  }

  return copyKeyframesByKey.get(key);
}

/**
 * The colours a streamed character in `textColor`, a computed CSS colour, takes every
 * `STREAMED_CHARACTER_SAMPLE_INTERVAL_MS` over `STREAMED_CHARACTER_DURATION_MS`: its own colour, as transparent as the
 * character is, with the Agent's blue and violet over it, as one colour. A colour that cannot be read has none.
 */
export function getStreamedCharacterColors(textColor: string, isDark: boolean) {
  const key = `${isDark ? 'dark' : 'light'}:${textColor}`;
  if (!colorsByKey.has(key)) {
    const color = parseCssColor(textColor);
    colorsByKey.set(key, color && buildStreamedCharacterColors(color, getAgentTextColors(isDark)));
  }

  return colorsByKey.get(key);
}

/**
 * The keyframes of the glow of a streamed character in `textColor` over `STREAMED_CHARACTER_DURATION_MS`, as the shadow
 * of a copy of the character that shows nothing else. A character whose colour cannot be read glows as an opaque one.
 */
export function getStreamedCharacterGlowKeyframes(textColor: string, isDark: boolean) {
  const key = `${isDark ? 'dark' : 'light'}:${textColor}`;
  let keyframes = glowKeyframesByKey.get(key);
  if (!keyframes) {
    keyframes = buildStreamedCharacterGlowKeyframes(parseCssColor(textColor)?.alpha ?? 1, getAgentTextColors(isDark));
    glowKeyframesByKey.set(key, keyframes);
  }

  return keyframes;
}

function buildStreamedCharacterColors(textColor: RgbaColor, colors: AgentGlowColors) {
  return getSampleAges().map((age) => (
    formatColor(compositeTint(textColor, getOpacity(age), colors, getTint(age)))
  ));
}

function buildStreamedCharacterGlowKeyframes(textAlpha: number, colors: AgentGlowColors): Keyframe[] {
  const ages = getSampleAges();

  return ages.map((age, index) => {
    const sharpness = getSharpness(age);
    // The glow is the character's own shadow, as strong as the character shows, so the tint over it takes no part in it
    const alpha = textAlpha * getOpacity(age) * INITIAL_GLOW_OPACITY * (1 - sharpness);
    return { offset: index / (ages.length - 1), textShadow: buildGlow(colors.blue, alpha, sharpness) };
  });
}

// The character's ages at its samples, in seconds, from its coming in to its settling
function getSampleAges() {
  const total = SHARPEN_DURATION + COLOR_DURATION;
  const sampleCount = Math.round(total / SAMPLE_INTERVAL);

  return Array.from({ length: sampleCount + 1 }, (_, index) => (total * index) / sampleCount);
}

function getSharpness(age: number) {
  return getBezierProgress(EASE_OUT, clamp(age / SHARPEN_DURATION));
}

function getOpacity(age: number) {
  return INITIAL_OPACITY + (1 - INITIAL_OPACITY) * getSharpness(age);
}

// The opacities of the Agent's blue over the character and of the violet over that, `age` seconds in, which together
// show the Agent's colours over the character's own: as much as the character shows while it sharpens, and less and
// less as it turns into its own colour
function getTint(age: number) {
  const sharpness = clamp(age / SHARPEN_DURATION);
  const toText = clamp((age - SHARPEN_DURATION) / COLOR_DURATION);
  const accent = (INITIAL_OPACITY + (1 - INITIAL_OPACITY) * sharpness) * (1 - toText);
  // Blue while it sharpens, violet by the middle of its turn into its own colour
  const violetProgress = clamp((age - SHARPEN_DURATION) / (COLOR_DURATION / 2));
  const violet = accent * violetProgress * violetProgress * (3 - 2 * violetProgress);
  const blue = violet < 1 ? (accent - violet) / (1 - violet) : 0;

  return { blue, violet };
}

// The character in its own colour at `opacity`, with the blue over it and the violet over that, as one colour
function compositeTint(
  textColor: RgbaColor,
  opacity: number,
  colors: AgentGlowColors,
  tint: { blue: number; violet: number },
): RgbaColor {
  const alpha = textColor.alpha * opacity;
  const layers: [AgentGlowColor, number][] = [[colors.blue, tint.blue], [colors.violet, tint.violet]];
  // Premultiplied red, green, blue and alpha
  const [red, green, blue, coverage] = layers.reduce<number[]>(
    (result, [color, layerAlpha]) => (
      [...color, 1].map((channel, index) => channel * layerAlpha + result[index] * (1 - layerAlpha))
    ),
    [textColor.red * alpha, textColor.green * alpha, textColor.blue * alpha, alpha],
  );
  // A transparent character with no tint over it shows nothing
  if (coverage === 0) {
    return {
      red: 0, green: 0, blue: 0, alpha: 0,
    };
  }

  return {
    red: red / coverage, green: green / coverage, blue: blue / coverage, alpha: coverage,
  };
}

// The glow is gone once the character is sharp
function buildGlow([red, green, blue]: AgentGlowColor, alpha: number, sharpness: number) {
  if (sharpness >= 1) return 'none';

  const blur = INITIAL_GLOW_BLUR * (1 - sharpness);
  return `0 0 ${blur.toFixed(2)}px ${formatColor({
    red, green, blue, alpha: Math.min(1, alpha),
  })}`;
}

function formatColor({
  red, green, blue, alpha,
}: RgbaColor) {
  return `rgba(${Math.round(red)}, ${Math.round(green)}, ${Math.round(blue)}, ${Number(alpha.toFixed(3))})`;
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}
