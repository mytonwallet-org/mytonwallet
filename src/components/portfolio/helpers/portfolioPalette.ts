export const TOKEN_TYPE_COLORS = {
  native: '#2C92F0',
  stablecoins: '#E49329',
  altcoins: '#10B853',
} as const;

export const STAKED_COLORS = {
  staked: '#6875E9',
  notStaked: '#2C92F0',
} as const;

// LovelyChart's built-in palette. Used across all portfolio charts so a token
// is rendered with the same color in net worth, P&L, and share charts.
export const DEFAULT_COLORS: readonly string[] = [
  '#3497ED',
  '#2373DB',
  '#9ED448',
  '#5FB641',
  '#F5BD25',
  '#F79E39',
  '#E65850',
  '#5D5CDC',
];
