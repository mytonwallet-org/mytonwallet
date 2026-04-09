import { SOLANA_DERIVATION_PATHS } from './constants';
import { extractIndexFromPath } from './wallet';

describe('extractIndexFromPath (Solana)', () => {
  it(`returns correct index for phantom path "m/44'/501'/4'/0'"`, () => {
    const path = `m/44'/501'/4'/0'`;
    expect(extractIndexFromPath(path)).toBe(4);
  });

  it(`returns 0 for phantom path "m/44'/501'/0'/0'"`, () => {
    const path = `m/44'/501'/0'/0'`;
    expect(extractIndexFromPath(path)).toBe(0);
  });

  it(`returns correct index for trust path "m/44'/501'/7'"`, () => {
    const path = `m/44'/501'/7'`;
    expect(extractIndexFromPath(path)).toBe(7);
  });

  it(`returns correct index for bip44Deprecated path "m/501'/3'/0'/0'"`, () => {
    const path = `m/501'/3'/0'/0'`;
    expect(extractIndexFromPath(path)).toBe(3);
  });

  it(`returns 0 for default path "m/44'/501'" (no {index})`, () => {
    const path = SOLANA_DERIVATION_PATHS.default; // `m/44'/501'`
    expect(extractIndexFromPath(path)).toBe(0);
  });

  it(`returns 0 for unknown path "m/44'/501'/999'/999'" that does not match any template`, () => {
    const path = `m/44'/501'/999'/999'`;
    expect(extractIndexFromPath(path)).toBe(0);
  });

  it(`returns 0 when path "m/44'/501'/4'/0'/extra" almost matches template but has extra suffix`, () => {
    const path = `m/44'/501'/4'/0'/extra`;
    expect(extractIndexFromPath(path)).toBe(0);
  });
});
