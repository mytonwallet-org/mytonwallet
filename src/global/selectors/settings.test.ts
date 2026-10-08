import type { GlobalState } from '../types';

type SettingsSelectors = typeof import('./settings');

// Config reads IS_GRAM_WALLET at module-eval time, so each flavor needs its own isolated import
async function loadSelectors(isGramWallet: boolean) {
  const savedFlag = process.env.IS_GRAM_WALLET;
  let selectors: SettingsSelectors | undefined;

  try {
    if (isGramWallet) {
      process.env.IS_GRAM_WALLET = '1';
    } else {
      delete process.env.IS_GRAM_WALLET;
    }

    await jest.isolateModulesAsync(async () => {
      selectors = await import('./settings');
    });
  } finally {
    if (savedFlag === undefined) {
      delete process.env.IS_GRAM_WALLET;
    } else {
      process.env.IS_GRAM_WALLET = savedFlag;
    }
  }

  return selectors!;
}

function makeGlobal(isGramDiamondEnabled?: true) {
  return {
    settings: { developerSettingsOverrides: isGramDiamondEnabled ? { isGramDiamondEnabled } : undefined },
  } as unknown as GlobalState;
}

describe('selectIsGramDiamondEnabled', () => {
  describe.each([
    ['My Wallet', false],
    ['Gram Wallet', true],
  ])('in %s', (_name, isGramWallet) => {
    let selectIsGramDiamondEnabled: SettingsSelectors['selectIsGramDiamondEnabled'];

    beforeAll(async () => {
      ({ selectIsGramDiamondEnabled } = await loadSelectors(isGramWallet));
    });

    it('hides the diamond without the developer override', () => {
      expect(selectIsGramDiamondEnabled(makeGlobal())).toBe(false);
    });

    it('shows the diamond after the developer override', () => {
      expect(selectIsGramDiamondEnabled(makeGlobal(true))).toBe(true);
    });
  });
});
