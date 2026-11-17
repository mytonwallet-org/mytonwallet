// The mask sizes match the text they cover: `rows * cellSize` is the line height, `cols * cellSize` the width.
// A row mask gives `min` and `max` instead of `cols`, and `SensitiveData` picks the width between them by `seed`, so
// the rows of one list get masks of different widths.

export const PERPS_AMOUNT_MASK = { cols: 10, rows: 3, cellSize: 13 };
export const PERPS_CHANGE_MASK = { cols: 12, rows: 2, cellSize: 10 };
export const PERPS_ROW_AMOUNT_MASK = { min: 4, max: 10, rows: 2, cellSize: 8 };
export const PERPS_ROW_PNL_MASK = { min: 5, max: 10, rows: 2, cellSize: 8 };
