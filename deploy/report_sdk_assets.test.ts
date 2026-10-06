const { describeBundle } = require('./report_sdk_assets');

// A minified bundle is one long line, and the stamp survives it as a plain string literal.
const MINIFIED = 'var e="0020277252 2026-09-30 01:40:07",t="https://agent-beta.mytonwallet.org/api";';

describe('describeBundle', () => {
  it('finds the build stamp a shipped bundle carries', () => {
    expect(describeBundle(MINIFIED).stamp).toBe('0020277252 2026-09-30 01:40:07');
  });

  // `--short=9` returns a longer prefix whenever nine characters would be ambiguous, and a tree
  // without git history stamps `nogit`. A pattern tied to one length fails those builds outright.
  it('accepts every shape the stamp is written in', () => {
    expect(describeBundle('e="af0012345 2026-09-30 01:40:07"').stamp).toBe('af0012345 2026-09-30 01:40:07');
    expect(describeBundle('e="af0012345-dirty 2026-09-30 01:40:07"').stamp).toBe('af0012345-dirty 2026-09-30 01:40:07');
    expect(describeBundle('e="nogit 2026-09-30 01:40:07"').stamp).toBe('nogit 2026-09-30 01:40:07');
  });

  // A bundle built before the stamp existed looks exactly like a fresh one otherwise, so its
  // absence has to be reportable rather than silently empty.
  it('reports no stamp instead of guessing when the bundle predates stamping', () => {
    expect(describeBundle('var e="https://agent-beta.mytonwallet.org/api";').stamp).toBeUndefined();
  });

  it('identifies a copy by content, which is what tells a fresh copy from a leftover', () => {
    expect(describeBundle(MINIFIED).sha256).toBe(describeBundle(MINIFIED).sha256);
    expect(describeBundle(MINIFIED).sha256).not.toBe(describeBundle(`${MINIFIED} `).sha256);
  });
});
