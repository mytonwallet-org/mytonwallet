import type { ApiNft } from '../../api/types';

import recipe from '../../../tests/fixtures/cardSurfaceRecipe.json';
import {
  getCardBorder,
  getCardSurfaceProfile,
  getCardTextPalette,
  getNativeCardMotionSeed,
} from './surfaceProfile';

function nft(type: ApiNft['metadata']['mtwCardType'], shine?: ApiNft['metadata']['mtwCardBorderShineType']): ApiNft {
  return {
    chain: 'ton',
    interface: 'default',
    index: 1,
    address: 'test-card',
    isOnSale: false,
    metadata: { mtwCardId: 1, mtwCardType: type, mtwCardBorderShineType: shine },
  };
}

it.each([
  ['standard', 0, 0.62],
  ['silver', 1, 0.62],
  ['gold', 1, 0.48],
  ['platinum', 1, 0.22],
  ['black', 2, 0.22],
] as const)('uses the native material and strength for %s', (type, material, intensity) => {
  expect(getCardSurfaceProfile(nft(type), false)).toMatchObject({ material, intensity, isCustom: true, isGram: false });
});

it('distinguishes both default wallets without treating them as an NFT material', () => {
  expect(getCardSurfaceProfile(undefined, false)).toMatchObject({ isCustom: false, isGram: false });
  expect(getCardSurfaceProfile(undefined, true)).toMatchObject({ isCustom: false, isGram: true });
});

it.each([
  ['up', -80],
  ['down', 70],
  ['left', -190],
  ['right', 10],
] as const)('retains the native resting highlight for %s', (shine, angle) =>
  expect(getCardBorder(nft('standard', shine), true).angle).toBe(angle),
);

it('keeps radioactive green and the light-theme Black rim rather than imposing the dark-theme colors', () => {
  const rim = (card: ApiNft, isDark: boolean) => decodeURIComponent(
    getCardBorder(card, isDark).backgroundForSize(358, 208),
  );
  expect(rim(nft('standard', 'radioactive'), true)).toContain('rgb(92,232,80)');
  expect(rim(nft('black'), false)).toContain('stop-opacity="0.24"');
  expect(getCardTextPalette(nft('gold'))).toEqual(['#4C3403', '#B07D1D']);
});

it('hashes the native trait recipe, so identical artwork keeps its phase across wallets', () => {
  const card = nft('standard');

  card.metadata.attributes = Object.entries(recipe.traits).map(([trait_type, value]) => ({
    trait_type,
    value: String(value),
  }));

  expect(getNativeCardMotionSeed(card)).toBe(recipe.seed);
  expect(getNativeCardMotionSeed({ ...card, address: 'another-owner-card' })).toBe(recipe.seed);
});

// Home screen presets from iOS `CardMotionPreset.swift` (PR #13087): only the Gram card shines
it.each([undefined, 'standard', 'silver', 'gold', 'platinum', 'black'] as const)(
  'leaves %s without shine in both brands', (type) => {
    for (const brand of [false, true]) {
      if (!type && brand) continue;

      expect(getCardSurfaceProfile(type ? nft(type) : undefined, brand).shineOpacity).toBe(0);
    }
  },
);

it('keeps Gram cyan reflection independent from material lighting', () => {
  expect(getCardSurfaceProfile(undefined, true)).toMatchObject({
    shineOpacity: 0.33, gramWidth: 120, gramBlur: 18, intensity: 0,
  });
  expect(getCardSurfaceProfile(undefined, false).intensity).toBe(0.28);
});

it('uses the same standard material for both text colors and for missing type metadata', () => {
  const light = nft('standard');
  light.metadata.mtwCardTextType = 'light';

  const dark = { ...light, metadata: { ...light.metadata, mtwCardTextType: 'dark' as const } };
  expect(getCardSurfaceProfile(light, false)).toEqual(getCardSurfaceProfile(dark, false));
  expect(getCardSurfaceProfile(nft(undefined), false).intensity).toBe(0.62);
});

it('does not invent a shine direction for a standard card without that trait', () => {
  expect(getCardBorder(nft('standard'), true).angle).toBeUndefined();
});
