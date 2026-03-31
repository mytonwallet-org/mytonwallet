declare module 'ffjavascript' {
  export const buildBls12381: any;
  export const utils: {
    unstringifyBigInts: <T extends Record<string, any>>(record: T) => Record<keyof T, bigint>;
  };

  // whatever else you want loosely typed:
  export type Curve = Record<string, any>;
}
