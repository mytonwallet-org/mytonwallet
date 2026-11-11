/** A colour as its red, green and blue, from 0 to 255 */
export type AgentGlowColor = [number, number, number];

export interface AgentGlowColors {
  blue: AgentGlowColor;
  violet: AgentGlowColor;
}

// The Agent's blue and violet, as iOS's `AgentGlowPalette` has them
const DEEP_COLORS: AgentGlowColors = { blue: [5, 109, 205], violet: [144, 70, 203] };
const BRIGHT_COLORS: AgentGlowColors = { blue: [50, 158, 255], violet: [190, 118, 253] };

/** The thinking glow lays the deep pair on dark, where it adds light, and the bright pair over light */
export function getAgentGlowColors(isDark: boolean) {
  return isDark ? DEEP_COLORS : BRIGHT_COLORS;
}

/** Text in the Agent's colours takes the pair that stands out from the background, the other way round from the glow */
export function getAgentTextColors(isDark: boolean) {
  return isDark ? BRIGHT_COLORS : DEEP_COLORS;
}

export function getIsDarkTheme() {
  return document.documentElement.classList.contains('theme-dark');
}
