// Guards the two orthogonal build axes that the wallet.ton.org combo profile introduced:
//   - behavior/storage axis, driven by IS_CORE_WALLET (Core behavior)
//   - brand axis, driven by IS_GRAM_WALLET (Gram branding), with IS_TON_BRAND = IS_CORE_WALLET && !IS_GRAM_WALLET
// The combo build (both flags) must inherit Core behavior/storage while wearing the Gram brand, and
// the three clean flavors (default / core / gram) must keep resolving exactly as before. Config reads
// the flags from process.env at module-eval time, so every flavor gets a clean env + an isolated re-import.

type Flavor = 'default' | 'core' | 'gram' | 'combo';

const FLAVORS: Flavor[] = ['default', 'core', 'gram', 'combo'];

// Only these env vars feed the constants under test; reset them all, then set the profile's subset.
const AXIS_FLAGS = ['IS_CORE_WALLET', 'IS_GRAM_WALLET', 'IS_EXPLORER', 'APP_NAME'] as const;

const FLAVOR_ENV: Record<Flavor, Partial<Record<'IS_CORE_WALLET' | 'IS_GRAM_WALLET', '1'>>> = {
  default: {},
  core: { IS_CORE_WALLET: '1' },
  gram: { IS_GRAM_WALLET: '1' },
  combo: { IS_CORE_WALLET: '1', IS_GRAM_WALLET: '1' },
};

type ConfigModule = typeof import('./config');
type DeeplinkModule = typeof import('./util/deeplink/constants');
type ChainModule = typeof import('./util/chain');
type TokensModule = typeof import('./util/tokens');

const savedEnv: Partial<Record<(typeof AXIS_FLAGS)[number], string | undefined>> = {};

beforeAll(() => {
  for (const key of AXIS_FLAGS) {
    savedEnv[key] = process.env[key];
  }
});

afterAll(() => {
  for (const key of AXIS_FLAGS) {
    const previous = savedEnv[key];
    if (previous === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = previous;
    }
  }
});

async function withFlavor(
  flavor: Flavor,
  run: (config: ConfigModule, deeplink: DeeplinkModule, chain: ChainModule, tokens: TokensModule) => void,
) {
  for (const key of AXIS_FLAGS) {
    delete process.env[key];
  }
  for (const [key, value] of Object.entries(FLAVOR_ENV[flavor])) {
    process.env[key] = value;
  }

  await jest.isolateModulesAsync(async () => {
    // All modules resolve inside the same fresh registry, so they see the same config instance.
    const config = await import('./config');
    const deeplink = await import('./util/deeplink/constants');
    const chain = await import('./util/chain');
    const tokens = await import('./util/tokens');
    run(config, deeplink, chain, tokens);
  });
}

// Behavior/storage + brand constants.
const CONFIG_EXPECTATIONS: Record<Flavor, Record<string, string | boolean | number[]>> = {
  default: {
    APP_NAME: 'My Wallet',
    IS_TON_BRAND: false,
    GLOBAL_STATE_CACHE_KEY: 'mytonwallet-global-state',
    ACTIVE_TAB_STORAGE_KEY: 'mtw-active-tab',
    TONCONNECT_WALLET_JSBRIDGE_KEY: 'mytonwallet',
    PRODUCTION_URL: 'https://web.mywallet.io',
    BETA_URL: 'https://beta.mywallet.io',
    APP_INSTALL_URL: 'https://get.mywallet.io/',
    APP_WEBSITE_URL: 'https://mywallet.io',
    SHOULD_GENERATE_TON_MNEMONIC: false,
    MNEMONIC_COUNTS: [12, 24],
    IS_STAKING_DISABLED: false,
    SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY: false,
    WINDOW_PROVIDER_PORT: 'MyWallet_popup_reversed',
  },
  core: {
    APP_NAME: 'TON Wallet',
    IS_TON_BRAND: true,
    GLOBAL_STATE_CACHE_KEY: 'tonwallet-global-state',
    ACTIVE_TAB_STORAGE_KEY: 'tw-active-tab',
    TONCONNECT_WALLET_JSBRIDGE_KEY: 'tonwallet',
    PRODUCTION_URL: 'https://wallet.ton.org',
    BETA_URL: 'https://beta.wallet.ton.org',
    APP_INSTALL_URL: 'https://get.mywallet.io/',
    APP_WEBSITE_URL: 'https://mywallet.io',
    SHOULD_GENERATE_TON_MNEMONIC: true,
    MNEMONIC_COUNTS: [24, 12],
    IS_STAKING_DISABLED: true,
    SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY: true,
    WINDOW_PROVIDER_PORT: 'TonWallet_popup_reversed',
  },
  gram: {
    APP_NAME: 'Gram Wallet',
    IS_TON_BRAND: false,
    GLOBAL_STATE_CACHE_KEY: 'mytonwallet-global-state',
    ACTIVE_TAB_STORAGE_KEY: 'mtw-active-tab',
    TONCONNECT_WALLET_JSBRIDGE_KEY: 'mytonwallet',
    PRODUCTION_URL: 'https://web.mywallet.io',
    BETA_URL: 'https://beta.mywallet.io',
    APP_INSTALL_URL: 'https://get.gramwallet.io/',
    APP_WEBSITE_URL: 'https://gramwallet.io',
    SHOULD_GENERATE_TON_MNEMONIC: false,
    MNEMONIC_COUNTS: [12, 24],
    IS_STAKING_DISABLED: false,
    SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY: false,
    WINDOW_PROVIDER_PORT: 'MyWallet_popup_reversed',
  },
  // The crux: Gram brand strings, Core behavior/storage strings.
  combo: {
    APP_NAME: 'Gram Wallet',
    IS_TON_BRAND: false,
    GLOBAL_STATE_CACHE_KEY: 'tonwallet-global-state',
    ACTIVE_TAB_STORAGE_KEY: 'tw-active-tab',
    TONCONNECT_WALLET_JSBRIDGE_KEY: 'tonwallet',
    PRODUCTION_URL: 'https://wallet.ton.org',
    BETA_URL: 'https://beta.wallet.ton.org',
    APP_INSTALL_URL: 'https://get.gramwallet.io/',
    APP_WEBSITE_URL: 'https://gramwallet.io',
    SHOULD_GENERATE_TON_MNEMONIC: true,
    MNEMONIC_COUNTS: [24, 12],
    IS_STAKING_DISABLED: true,
    SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY: true,
    WINDOW_PROVIDER_PORT: 'TonWallet_popup_reversed',
  },
};

// Deeplink constants are pure brand-axis (IS_GRAM_WALLET), so core stays on the non-Gram values
// while combo flips to Gram — proving the brand axis is independent of the behavior axis.
const DEEPLINK_EXPECTATIONS: Record<Flavor, {
  SELF_PROTOCOL: string;
  TONCONNECT_UNIVERSAL_URL: string;
  SELF_UNIVERSAL_URLS: string[];
}> = {
  default: {
    SELF_PROTOCOL: 'mtw://',
    TONCONNECT_UNIVERSAL_URL: 'https://connect.mytonwallet.org',
    SELF_UNIVERSAL_URLS: ['https://my.tt', 'https://go.mytonwallet.org'],
  },
  core: {
    SELF_PROTOCOL: 'mtw://',
    TONCONNECT_UNIVERSAL_URL: 'https://connect.mytonwallet.org',
    SELF_UNIVERSAL_URLS: ['https://my.tt', 'https://go.mytonwallet.org'],
  },
  gram: {
    SELF_PROTOCOL: 'gramwallet://',
    TONCONNECT_UNIVERSAL_URL: 'https://connect.gramwallet.io',
    SELF_UNIVERSAL_URLS: ['https://go.gramwallet.io'],
  },
  combo: {
    SELF_PROTOCOL: 'gramwallet://',
    TONCONNECT_UNIVERSAL_URL: 'https://connect.gramwallet.io',
    SELF_UNIVERSAL_URLS: ['https://go.gramwallet.io'],
  },
};

describe.each(FLAVORS)('build flavor: %s', (flavor) => {
  it('resolves brand/behavior config constants', async () => {
    await withFlavor(flavor, (config) => {
      const expected = CONFIG_EXPECTATIONS[flavor];
      const actual: Record<string, string | boolean | number[]> = {
        APP_NAME: config.APP_NAME,
        IS_TON_BRAND: config.IS_TON_BRAND,
        GLOBAL_STATE_CACHE_KEY: config.GLOBAL_STATE_CACHE_KEY,
        ACTIVE_TAB_STORAGE_KEY: config.ACTIVE_TAB_STORAGE_KEY,
        TONCONNECT_WALLET_JSBRIDGE_KEY: config.TONCONNECT_WALLET_JSBRIDGE_KEY,
        PRODUCTION_URL: config.PRODUCTION_URL,
        BETA_URL: config.BETA_URL,
        APP_INSTALL_URL: config.APP_INSTALL_URL,
        APP_WEBSITE_URL: config.APP_WEBSITE_URL,
        SHOULD_GENERATE_TON_MNEMONIC: config.SHOULD_GENERATE_TON_MNEMONIC,
        MNEMONIC_COUNTS: config.MNEMONIC_COUNTS,
        IS_STAKING_DISABLED: config.IS_STAKING_DISABLED,
        SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY: config.SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
        WINDOW_PROVIDER_PORT: config.WINDOW_PROVIDER_PORT,
      };
      // Compare the whole object so a single failing run lists every mismatched axis at once.
      expect(actual).toEqual(expected);
    });
  });

  it('resolves brand-axis deeplink constants', async () => {
    await withFlavor(flavor, (_config, deeplink) => {
      const expected = DEEPLINK_EXPECTATIONS[flavor];
      expect(deeplink.SELF_PROTOCOL).toBe(expected.SELF_PROTOCOL);
      expect(deeplink.TONCONNECT_UNIVERSAL_URL).toBe(expected.TONCONNECT_UNIVERSAL_URL);
      expect(deeplink.SELF_UNIVERSAL_URLS).toEqual(expected.SELF_UNIVERSAL_URLS);
    });
  });
});

describe('getDefaultEnabledSlugs resolves per behavior axis', () => {
  // Chains of the default-enabled token set per flavor. This is what puts zero-balance rows on an
  // empty wallet's home screen, so for Core/combo it must stay TON-only (the wallet.ton.org storefront).
  const chainsByFlavor: Partial<Record<Flavor, Set<string>>> = {};

  beforeAll(async () => {
    for (const flavor of FLAVORS) {
      await withFlavor(flavor, (_config, _deeplink, chain, tokens) => {
        const slugs = [...chain.getDefaultEnabledSlugs('mainnet')];
        expect(slugs.length).toBeGreaterThan(0);
        chainsByFlavor[flavor] = new Set(slugs.map((slug) => tokens.getChainBySlug(slug)));
      });
    }
  });

  it('core and combo default to TON tokens only', () => {
    expect([...chainsByFlavor.core!]).toEqual(['ton']);
    expect([...chainsByFlavor.combo!]).toEqual(['ton']);
  });

  it('default and gram keep the multichain defaults', () => {
    expect(chainsByFlavor.default).toEqual(chainsByFlavor.gram);
    expect(chainsByFlavor.default!.size).toBeGreaterThan(1);
  });
});

describe('TON_DNS_ZONES resolves per behavior axis', () => {
  // Suffix signatures per flavor: each zone -> its suffixes array, joined for stable comparison.
  const signatureByFlavor: Partial<Record<Flavor, string[]>> = {};

  beforeAll(async () => {
    for (const flavor of FLAVORS) {
      await withFlavor(flavor, (config) => {
        signatureByFlavor[flavor] = config.TON_DNS_ZONES.map((zone) => zone.suffixes.join('|'));
      });
    }
  });

  it('combo keeps the t.me zone (needed for Telegram avatars)', () => {
    expect(signatureByFlavor.combo).toContain('t.me');
  });

  it('combo uses the same official DNS set as core', () => {
    expect(signatureByFlavor.combo).toEqual(signatureByFlavor.core);
  });

  it('default and gram expose the full (superset) DNS set', () => {
    expect(signatureByFlavor.gram).toEqual(signatureByFlavor.default);
    expect(signatureByFlavor.default!.length).toBeGreaterThan(signatureByFlavor.core!.length);
    // The official (core/combo) set must be a subset of the full (default/gram) set.
    const fullSet = new Set(signatureByFlavor.default);
    for (const suffix of signatureByFlavor.core!) {
      expect(fullSet.has(suffix)).toBe(true);
    }
  });
});
