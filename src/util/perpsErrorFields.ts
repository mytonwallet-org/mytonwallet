export const PERPS_ERROR_AMOUNT_KEYS = [
  'minimumAmount', 'minimumReduction', 'requiredBalance', 'availableBalance',
] as const;

/** The own fields of a Perps SDK error that the trade screens read, and the only ones an encoded error carries */
export const PERPS_ERROR_FIELD_KEYS = new Set<string>([...PERPS_ERROR_AMOUNT_KEYS, 'isMinimumExclusive']);
