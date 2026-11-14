export const COLOR_COUNT = 2;
export const QUALITY = 1;

export const ACCENT_CSS_VARIABLES = [
  '--color-accent',
  '--color-accent-10o',
  '--agent-link-decoration',
  '--color-accent-button-background',
  '--color-accent-button-background-hover',
  '--color-accent-button-text',
  '--color-accent-button-text-hover',
] as const;

export type AccentCssVariable = (typeof ACCENT_CSS_VARIABLES)[number];

export const ACCENT_COLORS = {
  light: [
    '#31AFC7', '#35C759', '#FF9500', '#FF2C55',
    '#AF52DE', '#5856D7', '#73AAED', '#FFB07A',
    '#B76C78', '#9689D1', '#E572CC', '#6BA07A',
    '#338FCC', '#1FC863', '#929395', '#E4B102',
    '#000000',
  ],
  dark: [
    '#3AB5CC', '#32D74B', '#FF9F0B', '#FF325A',
    '#BF5AF2', '#7977FF', '#73AAED', '#FFB07A',
    '#B76C78', '#9689D1', '#E572CC', '#6BA07A',
    '#338FCC', '#2CD36F', '#C3C5C6', '#DDBA00',
    '#FFFFFF',
  ],
} as const;
export const ACCENT_RADIOACTIVE_INDEX = 13;
export const ACCENT_SILVER_INDEX = 14;
export const ACCENT_GOLD_INDEX = 15;
export const ACCENT_BNW_INDEX = 16;

const excludedIndices = new Set([
  ACCENT_RADIOACTIVE_INDEX,
  ACCENT_SILVER_INDEX,
  ACCENT_GOLD_INDEX,
  ACCENT_BNW_INDEX,
]);

export const COLORS_TO_DETECT = ACCENT_COLORS.light
  .map((color, index) => ({ color, index }))
  .filter(({ index }) => !excludedIndices.has(index));
