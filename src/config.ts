/* eslint-disable @stylistic/max-len */
import type { ApiTonWalletVersion } from './api/chains/ton/types';
import type {
  ApiBaseCurrency,
  ApiChain,
  ApiLiquidStakingState,
  ApiNftMarketplace,
  ApiNominatorsStakingState,
  ApiSwapAsset,
  ApiSwapDexLabel,
} from './api/types';
import type { TOKEN_CARD_COLORS } from './components/main/helpers/cardColors';
import type { AutolockValueType, LangCode, LangItem, TokenPeriod } from './global/types';

export const APP_ENV = process.env.APP_ENV || 'production';

export const IS_CORE_WALLET = process.env.IS_CORE_WALLET === '1';
export const APP_NAME = process.env.APP_NAME || (IS_CORE_WALLET ? 'TON Wallet' : 'MyTonWallet');
export const APP_VERSION = process.env.APP_VERSION!;
export const APP_COMMIT_HASH = process.env.APP_COMMIT_HASH!;
export const APP_ENV_MARKER = APP_ENV === 'staging' ? 'Beta' : APP_ENV === 'development' ? 'Dev' : undefined;
export const EXTENSION_NAME = IS_CORE_WALLET ? 'TON Wallet' : 'MyTonWallet · My TON Wallet';
export const EXTENSION_DESCRIPTION = IS_CORE_WALLET
  ? 'Set up your own TON Wallet on The Open Network'
  : 'The most feature-rich TON+TRON wallet: multi-accounts, multi-send, Telegram Gifts and other collectibles, TON DNS+Proxy, and more.';

export const DEBUG = APP_ENV !== 'production' && APP_ENV !== 'perf' && APP_ENV !== 'test';
export const DEBUG_MORE = false;
export const DEBUG_API = false;
export const DEBUG_VIEW_ACCOUNTS = false;

export const IS_PRODUCTION = APP_ENV === 'production';
export const IS_TEST = APP_ENV === 'test';
export const IS_PERF = APP_ENV === 'perf';
export const IS_EXTENSION = process.env.IS_EXTENSION === '1';
export const IS_FIREFOX_EXTENSION = process.env.IS_FIREFOX_EXTENSION === '1';
export const IS_OPERA_EXTENSION = process.env.IS_OPERA_EXTENSION === '1';
export const IS_PACKAGED_ELECTRON = process.env.IS_PACKAGED_ELECTRON === '1';
export const IS_CAPACITOR = process.env.IS_CAPACITOR === '1';
export const IS_ANDROID_DIRECT = process.env.IS_ANDROID_DIRECT === '1';
export const IS_AIR_APP = process.env.IS_AIR_APP === '1';
export const IS_TELEGRAM_APP = process.env.IS_TELEGRAM_APP === '1';
export const IS_EXPLORER = process.env.IS_EXPLORER === '1';

export const ELECTRON_HOST_URL = 'https://dumb-host';
export const INACTIVE_MARKER = '[Inactive]';
export const PRODUCTION_URL = IS_CORE_WALLET ? 'https://wallet.ton.org' : 'https://mytonwallet.app';
export const BETA_URL = IS_CORE_WALLET ? 'https://beta.wallet.ton.org' : 'https://beta.mytonwallet.app';
export const APP_INSTALL_URL = 'https://get.mytonwallet.io/';
export const APP_REPO_URL = 'https://github.com/mytonwallet-org/mytonwallet';
export const SELF_UNIVERSAL_HOST_URL = 'https://my.tt';

// GitHub workflow uses an empty string as the default value if it's not in repository variables, so we cannot define a default value here
export const BASE_URL = process.env.BASE_URL || PRODUCTION_URL;

export const BOT_USERNAME = process.env.BOT_USERNAME || 'MyTonWalletBot';

export const SWAP_FEE_ADDRESS = process.env.SWAP_FEE_ADDRESS || 'UQDUkQbpTVIgt7v66-JTFR-3-eXRFz_4V66F-Ufn6vOg0GOp';
export const DIESEL_ADDRESS = process.env.DIESEL_ADDRESS || 'UQC9lQOaEHC6YASiJJ2NrKEOlITMMQmc8j0_iZEHy-4sl3tG';

export const STRICTERDOM_ENABLED = DEBUG && !IS_PACKAGED_ELECTRON;

export const DEBUG_ALERT_MSG = 'Shoot!\nSomething went wrong, please see the error details in Dev Tools Console.';

export const PIN_LENGTH = 4;
export const NATIVE_BIOMETRICS_USERNAME = IS_CORE_WALLET ? 'TonWallet' : 'MyTonWallet';
export const NATIVE_BIOMETRICS_SERVER = IS_CORE_WALLET ? 'https://wallet.ton.org' : 'https://mytonwallet.app';
export const NATIVE_BIOMETRICS_PROMPT_KEY = 'confirm an action in MyTonWallet';

/** If `true`, the app supports only TON-specific mnemonics */
export const IS_TON_MNEMONIC_ONLY = IS_CORE_WALLET;

export const MNEMONIC_COUNT = 24;
export const MNEMONIC_COUNTS = IS_TON_MNEMONIC_ONLY ? [24] : [12, 24];

export const PRIVATE_KEY_HEX_LENGTH = 64;
export const MNEMONIC_CHECK_COUNT = 3;

export const MOBILE_SCREEN_MAX_WIDTH = 700; // px

export const VIEW_TRANSITION_CLASS_NAME = 'active-view-transition';

export const ANIMATION_END_DELAY = 50;

export const ANIMATED_STICKER_TINY_ICON_PX = 16;
export const ANIMATED_STICKER_ICON_PX = 30;
export const ANIMATED_STICKER_TINY_SIZE_PX = 70;
export const ANIMATED_STICKER_SMALL_SIZE_PX = 110;
export const ANIMATED_STICKER_MIDDLE_SIZE_PX = 120;
export const ANIMATED_STICKER_DEFAULT_PX = 150;
export const ANIMATED_STICKER_BIG_SIZE_PX = 156;
export const ANIMATED_STICKER_HUGE_SIZE_PX = 192;

export const DEFAULT_PORTRAIT_WINDOW_SIZE = { width: 368, height: 770 };
export const DEFAULT_LANDSCAPE_WINDOW_SIZE = { width: 980, height: 788 };
export const DEFAULT_LANDSCAPE_ACTION_TAB_ID = 0;
export const TRANSACTION_ADDRESS_SHIFT = 4;

export const WHOLE_PART_DELIMITER = ' '; // https://www.compart.com/en/unicode/U+202F

export const DEFAULT_SLIPPAGE_VALUE = 5;

export const GLOBAL_STATE_CACHE_DISABLED = false;
export const GLOBAL_STATE_CACHE_KEY = IS_CORE_WALLET
  ? 'tonwallet-global-state'
  : IS_EXPLORER
    ? 'explorer-global-state'
    : 'mytonwallet-global-state';

export const ANIMATION_LEVEL_MIN = 0;
export const ANIMATION_LEVEL_MED = 1;
export const ANIMATION_LEVEL_MAX = 2;
export const ANIMATION_LEVEL_DEFAULT = ANIMATION_LEVEL_MAX;
export const THEME_DEFAULT = 'system';

export const MAIN_ACCOUNT_ID = '0-ton-mainnet';
export const TEMPORARY_ACCOUNT_NAME = 'Wallet';

export const TONCENTER_MAINNET_URL = process.env.TONCENTER_MAINNET_URL || 'https://toncenter.mytonwallet.org';
export const TONCENTER_MAINNET_KEY = process.env.TONCENTER_MAINNET_KEY;
export const ELECTRON_TONCENTER_MAINNET_KEY = process.env.ELECTRON_TONCENTER_MAINNET_KEY;
export const TONAPIIO_MAINNET_URL = process.env.TONAPIIO_MAINNET_URL || 'https://tonapiio.mytonwallet.org';

export const TONCENTER_TESTNET_URL = process.env.TONCENTER_TESTNET_URL || 'https://toncenter-testnet.mytonwallet.org';
export const TONCENTER_TESTNET_KEY = process.env.TONCENTER_TESTNET_KEY;
export const ELECTRON_TONCENTER_TESTNET_KEY = process.env.ELECTRON_TONCENTER_TESTNET_KEY;
export const TONAPIIO_TESTNET_URL = process.env.TONAPIIO_TESTNET_URL || 'https://tonapiio-testnet.mytonwallet.org';

export const BRILLIANT_API_BASE_URL = process.env.BRILLIANT_API_BASE_URL || 'https://api.mytonwallet.org';
export const PROXY_API_BASE_URL = process.env.PROXY_API_BASE_URL || 'https://api.mytonwallet.org/proxy';
export const IPFS_GATEWAY_BASE_URL = 'https://ipfs.io/ipfs/';
export const SSE_BRIDGE_URL = 'https://tonconnectbridge.mytonwallet.org/bridge/';

export const WALLET_CONNECT_BRIDGE_PATTERNS = 'https://*.walletconnect.com https://*.walletconnect.org wss://*.walletconnect.com wss://*.walletconnect.org';

export const WALLET_CONNECT_PROJECT_ID = process.env.WALLET_CONNECT_PROJECT_ID || '';

export const TRON_MAINNET_API_URL = process.env.TRON_MAINNET_API_URL || 'https://tronapi.mytonwallet.org';
export const TRON_TESTNET_API_URL = process.env.TRON_TESTNET_API_URL || 'https://api.shasta.trongrid.io';

export const SOLANA_MAINNET_RPC_URL = process.env.SOLANA_MAINNET_RPC_URL || 'https://solanaapi.mytonwallet.org';
export const SOLANA_MAINNET_API_KEY = process.env.SOLANA_MAINNET_API_KEY;
export const SOLANA_TESTNET_RPC_URL = process.env.SOLANA_TESTNET_RPC_URL || 'https://solanaapi-devnet.mytonwallet.org';
export const SOLANA_TESTNET_API_KEY = process.env.SOLANA_TESTNET_API_KEY;
export const SOLANA_TESTNET_API_URL = process.env.SOLANA_TESTNET_API_URL || 'https://solanaapi-devnet.mytonwallet.org';
export const SOLANA_MAINNET_API_URL = process.env.SOLANA_MAINNET_API_URL || 'https://solanaapi.mytonwallet.org';

export const FRACTION_DIGITS = 9;
export const SHORT_FRACTION_DIGITS = 2;

export const MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT = 3;

export const SUPPORT_USERNAME = 'mysupport';
export const MTW_NEWS_CHANNEL_NAME: Partial<Record<LangCode, string>> = {
  en: 'MyTonWalletEn',
  ru: 'MyTonWalletRu',
};
export const MTW_TIPS_CHANNEL_NAME: Partial<Record<LangCode, string>> = {
  en: 'MyTonWalletTips',
  ru: 'MyTonWalletTipsRu',
};
export const NFT_MARKETPLACE_TITLES: Record<ApiNftMarketplace, string> = {
  getgems: 'Getgems',
  fragment: 'Fragment',
};
export const MTW_STATIC_BASE_URL = 'https://static.mytonwallet.org';
export const MTW_CARDS_BASE_URL = `${MTW_STATIC_BASE_URL}/cards/v2/cards/`;
export const MTW_CARDS_MINT_BASE_URL = `${MTW_STATIC_BASE_URL}/mint-cards/`;
export const MYTONWALLET_PROMO_URL = 'https://mytonwallet.io/';
export const MYTONWALLET_MULTISEND_DAPP_URL = 'https://multisend.mytonwallet.io/';
export const MYTONWALLET_BLOG: Partial<Record<LangCode, string>> = {
  en: 'https://mytonwallet.io/en/blog/',
  ru: 'https://mytonwallet.io/ru/blog/',
};
export const MYTONWALLET_TERMS_OF_USE_URL = 'https://mytonwallet.io/terms-of-use';
export const MYTONWALLET_PRIVACY_POLICY_URL = 'https://mytonwallet.io/privacy-policy';
export const NFT_MARKETPLACE_URL = 'https://getgems.io/';
export const NFT_MARKETPLACE_TITLE = NFT_MARKETPLACE_TITLES.getgems;
export const GETGEMS_BASE_MAINNET_URL = 'https://getgems.io/';
export const GETGEMS_BASE_TESTNET_URL = 'https://testnet.getgems.io/';
export const EMPTY_HASH_VALUE = 'NOHASH';

export const IFRAME_WHITELIST = [
  'http://localhost:*',
  'https://tonscan.org',
  'https://testnet.tonscan.org',
  'https://tonviewer.com',
  'https://testnet.tonviewer.com',
];
export const SUBPROJECT_URL_MASK = 'https://*.mytonwallet.io';

export const CHANGELLY_SUPPORT_EMAIL = 'support@changelly.com';
export const CHANGELLY_LIVE_CHAT_URL = 'https://changelly.com/';
export const CHANGELLY_SECURITY_EMAIL = 'security@changelly.com';
export const CHANGELLY_TERMS_OF_USE = 'https://changelly.com/terms-of-use';
export const CHANGELLY_PRIVACY_POLICY = 'https://changelly.com/privacy-policy';
export const CHANGELLY_AML_KYC = 'https://changelly.com/aml-kyc';
export const CHANGELLY_WAITING_DEADLINE = 3 * 60 * 60 * 1000; // 3 hours

export const PROXY_HOSTS = process.env.PROXY_HOSTS;

export const TINY_TRANSFER_MAX_COST = 0.01;

export const IMAGE_CACHE_NAME = IS_EXPLORER ? 'explorer-image' : 'mtw-image';
export const LANG_CACHE_NAME = 'mtw-lang-278';

export const LANG_LIST: LangItem[] = [{
  langCode: 'en',
  name: 'English',
  nativeName: 'English',
  rtl: false,
}, {
  langCode: 'es',
  name: 'Spanish',
  nativeName: 'Español',
  rtl: false,
}, {
  langCode: 'ru',
  name: 'Russian',
  nativeName: 'Русский',
  rtl: false,
}, {
  langCode: 'zh-Hans',
  name: 'Chinese (Simplified)',
  nativeName: '简体',
  rtl: false,
}, {
  langCode: 'zh-Hant',
  name: 'Chinese (Traditional)',
  nativeName: '繁體',
  rtl: false,
}, {
  langCode: 'tr',
  name: 'Turkish',
  nativeName: 'Türkçe',
  rtl: false,
}, {
  langCode: 'de',
  name: 'German',
  nativeName: 'Deutsch',
  rtl: false,
}, {
  langCode: 'th',
  name: 'Thai',
  nativeName: 'ไทย',
  rtl: false,
}, {
  langCode: 'uk',
  name: 'Ukrainian',
  nativeName: 'Українська',
  rtl: false,
}, {
  langCode: 'pl',
  name: 'Polish',
  nativeName: 'Polski',
  rtl: false,
}];

export const IS_STAKING_DISABLED = IS_CORE_WALLET;
export const VALIDATION_PERIOD_MS = 65_536_000; // 18.2 h.
export const ONE_TON = 1_000_000_000n;
export const DEFAULT_FEE = 15_000_000n; // 0.015 TON
export const UNSTAKE_TON_GRACE_PERIOD = 20 * 60 * 1000; // 20 m.

export const STAKING_POOLS = process.env.STAKING_POOLS ? process.env.STAKING_POOLS.split(' ') : [];
export const LIQUID_POOL = process.env.LIQUID_POOL || 'EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o';
export const LIQUID_JETTON = process.env.LIQUID_JETTON || 'EQCqC6EhRJ_tpWngKxL6dV0k6DSnRUrs9GSVkLbfdCqsj6TE';
export const STAKING_MIN_AMOUNT = ONE_TON;
export const NOMINATORS_STAKING_MIN_AMOUNT = 10_000n * ONE_TON;
export const MIN_ACTIVE_STAKING_REWARDS = 100_000_000n; // 0.1 MY
// Staked tokens now showing with all other tokens, so we need to add a prefix to avoid collisions
export const STAKING_SLUG_PREFIX = 'staking-';

export const TONCONNECT_PROTOCOL_VERSION = 2;
export const TONCONNECT_WALLET_JSBRIDGE_KEY = IS_CORE_WALLET ? 'tonwallet' : 'mytonwallet';
export const EMBEDDED_DAPP_BRIDGE_CHANNEL = 'embedded-dapp-bridge';

export const NFT_FRAGMENT_COLLECTIONS = [
  '0:0e41dc1dc3c9067ed24248580e12b3359818d83dee0304fabcf80845eafafdb2', // Anonymous Telegram Numbers
  '0:80d78a35f955a14b679faa887ff4cd5bfc0f43b4a4eea2a7e6927f3701b273c2', // Telegram Usernames
];
export const NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX = /^https?:\/\/nft\.(fragment\.com\/gift\/[\w-]+-\d+)\.\w+$/i;
export const TELEGRAM_GIFTS_SUPER_COLLECTION = 'super:telegram-gifts';

export const MTW_CARDS_WEBSITE = 'https://cards.mytonwallet.io';
export const MTW_CARDS_COLLECTION = 'EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM';

export const TON_DNS_RENEWAL_WARNING_DAYS = 14;
export const TON_DNS_RENEWAL_NFT_WARNING_DAYS = 30;

export const TONCOIN = {
  name: 'Toncoin',
  symbol: 'TON',
  slug: 'toncoin',
  decimals: 9,
  chain: 'ton',
  cmcSlug: 'toncoin',
  priceUsd: 3.1,
} as const;

export const TRX = {
  name: 'TRON',
  symbol: 'TRX',
  slug: 'trx',
  decimals: 6,
  chain: 'tron',
  cmcSlug: 'tron',
} as const;

export const SOLANA = {
  name: 'Solana',
  symbol: 'SOL',
  slug: 'sol',
  decimals: 9,
  chain: 'solana',
  cmcSlug: 'solana',
} as const;

export const MYCOIN_MAINNET = {
  name: 'MyTonWallet Coin',
  symbol: 'MY',
  slug: 'ton-eqcfvnlrbn',
  decimals: 9,
  chain: 'ton',
  minterAddress: 'EQCFVNlRb-NHHDQfv3Q9xvDXBLJlay855_xREsq5ZDX6KN-w',
  image: 'https://imgproxy.mytonwallet.org/imgproxy/Qy038wCBKISofJ0hYMlj6COWma330cx3Ju1ZSPM2LRU/rs:fill:200:200:1/g:no/aHR0cHM6Ly9teXRvbndhbGxldC5pby9sb2dvLTI1Ni1ibHVlLnBuZw.webp',
} as const;

export const MYCOIN_TESTNET = {
  ...MYCOIN_MAINNET,
  slug: 'ton-kqawlxpebw',
  minterAddress: 'kQAWlxpEbwhCDFX9gp824ee2xVBhAh5VRSGWfbNFDddAbQoQ',
  image: undefined,
} as const;

export const STAKED_TON_SLUG = 'ton-eqcqc6ehrj';
export const STAKED_MYCOIN_SLUG = 'ton-eqcbzvsfwq';
export const MYCOIN_STAKING_POOL = 'EQC3roTiRRsoLzfYVK7yVVoIZjTEqAjQU3ju7aQ7HWTVL5o5';

export const ETHENA_STAKING_VAULT = 'EQChGuD1u0e7KUWHH5FaYh_ygcLXhsdG2nSHPXHW8qqnpZXW';
export const ETHENA_STAKING_MIN_AMOUNT = 1_000_000; // 1 USDe
export const ETHENA_ELIGIBILITY_CHECK_URL = 'https://t.me/id_app/start?startapp=cQeewNnc3pVphUcwY63WruKMQDpgePd1E7eMVoqphMZAdGoU9jwS4qRqrM1kSeaqrAiiDiC3EYAJPwZDGWqxZpw5vtGxmHma59XEt';

export const STON_PTON_ADDRESS = 'EQCM3B12QK1e4yZSf8GtBRT0aLMNyEsBc_DhVfRRtOEffLez';
export const STON_PTON_SLUG = 'ton-eqcm3b12qk';

export const DNS_IMAGE_GEN_URL = 'https://dns-image.mytonwallet.org/img?d=';

export const TRC20_USDT_MAINNET = {
  name: 'Tether USD',
  symbol: 'USDT',
  decimals: 6,
  chain: 'tron',
  slug: 'tron-tr7nhqjekq',
  tokenAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  label: 'TRC-20',
} as const;

export const TRC20_USDT_TESTNET = {
  ...TRC20_USDT_MAINNET,
  slug: 'tron-tg3xxyexbk',
  tokenAddress: 'TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs',
};

export const TON_USDT_MAINNET = {
  name: 'Tether USD',
  symbol: 'USD₮',
  chain: 'ton',
  slug: 'ton-eqcxe6mutq',
  decimals: 6,
  tokenAddress: 'EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs',
  image: 'https://imgproxy.mytonwallet.org/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp',
  label: 'TON',
  priceUsd: 1,
} as const;

// Where to get this token: https://t.me/testgiver_ton_usdt_bot
export const TON_USDT_TESTNET = {
  ...TON_USDT_MAINNET,
  slug: 'ton-kqd0gkbm8z',
  tokenAddress: 'kQD0GKBM8ZbryVk2aESmzfU6b9b_8era_IkvBSELujFZPsyy',
  image: undefined,
} as const;

export const TON_USDE = {
  name: 'Ethena USDe',
  symbol: 'USDe',
  chain: 'ton',
  tokenAddress: 'EQAIb6KmdfdDR7CN1GBqVJuP25iCnLKCvBlJ07Evuu2dzP5f',
  slug: 'ton-eqaib6kmdf',
  decimals: 6,
  image: 'https://imgproxy.toncenter.com/binMwUmcnFtjvgjp4wSEbsECXwfXUwbPkhVvsvpubNw/pr:small/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvVVNEZS5wbmc',
} as const;

export const TON_TSUSDE = {
  name: 'Ethena tsUSDe',
  symbol: 'tsUSDe',
  chain: 'ton',
  tokenAddress: 'EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr',
  slug: 'ton-eqdq5uuyph',
  decimals: 6,
  image: 'https://cache.tonapi.io/imgproxy/vGZJ7erwsWPo7DpVG_V7ygNn7VGs0szZXcNLHB_l0ms/rs:fill:200:200:1/g:no/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvdHNVU0RlLnBuZw.webp',
} as const;

export const SOLANA_USDT_MAINNET = {
  name: 'Tether USD',
  symbol: 'USDT',
  decimals: 6,
  chain: 'solana',
  slug: 'solana-es9vmfrzac',
  tokenAddress: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
  label: 'SOL',
  image: 'https://imgproxy.mytonwallet.org/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp',
  priceUsd: 1,
} as const;

export const SOLANA_USDС_MAINNET = {
  name: 'USD Coin',
  symbol: 'USDC',
  decimals: 6,
  chain: 'solana',
  slug: 'solana-epjfwdd5au',
  tokenAddress: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  label: 'SOL',
  image: 'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png',
  priceUsd: 1,
} as const;

/** The properties not returned by the backend, and therefore not stored in token objects */
export const TOKEN_CUSTOM_STYLES: Partial<Record<string, {
  fontIcon?: string;
  cardColor?: keyof typeof TOKEN_CARD_COLORS;
}>> = {
  [TONCOIN.slug]: {
    fontIcon: 'icon-chain-ton',
    cardColor: 'blue',
  },
  [TRX.slug]: {
    fontIcon: 'icon-chain-tron',
    cardColor: 'red',
  },
  [SOLANA.slug]: {
    fontIcon: 'icon-chain-solana',
    cardColor: 'purple',
  },
  [STAKED_TON_SLUG]: {
    cardColor: 'green',
  },
};

export const ALL_STAKING_POOLS = [
  LIQUID_POOL,
  MYCOIN_STAKING_POOL,
  ETHENA_STAKING_VAULT,
  TON_TSUSDE.tokenAddress,
];

export const PRIORITY_TOKEN_SLUGS = [
  TONCOIN.slug,
  TON_USDT_MAINNET.slug,
  TRX.slug,
  TRC20_USDT_MAINNET.slug,
  SOLANA.slug,
  SOLANA_USDT_MAINNET.slug,
] as string[];

export const INIT_SWAP_ASSETS: Record<'in' | 'out', ApiSwapAsset> = {
  in: {
    ...TONCOIN,
    isPopular: true,
  },
  out: {
    ...TON_USDT_MAINNET,
    isPopular: true,
  },
};

export const DEFAULT_SWAP_FIRST_TOKEN_SLUG = TONCOIN.slug;
export const DEFAULT_SWAP_SECOND_TOKEN_SLUG = TON_USDT_MAINNET.slug;
export const DEFAULT_SWAP_AMOUNT = '10';
export const DEFAULT_TRANSFER_TOKEN_SLUG = TONCOIN.slug;

export const SWAP_DEX_LABELS: Record<ApiSwapDexLabel, string> = {
  dedust: 'DeDust',
  ston: 'STON.fi',
};

export const ACTIVE_TAB_STORAGE_KEY = IS_CORE_WALLET
  ? 'tw-active-tab'
  : IS_EXPLORER
    ? 'explorer-active-tab'
    : 'mtw-active-tab';

export const INDEXED_DB_NAME = IS_EXPLORER ? 'explorer-keyval-store' : 'keyval-store';
export const INDEXED_DB_STORE_NAME = 'keyval';

export const WINDOW_PROVIDER_CHANNEL = 'windowProvider';
export const WINDOW_PROVIDER_PORT = `${IS_CORE_WALLET ? 'TonWallet' : 'MyTonWallet'}_popup_reversed`;

export const SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY = IS_CORE_WALLET;
export const PORTRAIT_MIN_ASSETS_TAB_VIEW = 4;
export const LANDSCAPE_MIN_ASSETS_TAB_VIEW = 6;

export const DEFAULT_PRICE_CURRENCY = 'USD';
export const CURRENCIES: Record<
  ApiBaseCurrency,
  // Get the fallback rates at https://api.mytonwallet.org/currency-rates
  { name: string; decimals: number; shortSymbol?: string; fallbackRate: string }
> = {
  USD: {
    name: 'US Dollar',
    decimals: 2,
    shortSymbol: '$',
    fallbackRate: '1',
  },
  EUR: {
    name: 'Euro',
    decimals: 2,
    shortSymbol: '€',
    fallbackRate: '0.85233500',
  },
  RUB: {
    name: 'Russian Ruble',
    decimals: 2,
    shortSymbol: '₽',
    fallbackRate: '84.49824600',
  },
  CNY: {
    name: 'Chinese Yuan',
    decimals: 2,
    shortSymbol: '¥',
    fallbackRate: '7.11865000',
  },
  BTC: {
    name: 'Bitcoin',
    decimals: 9,
    fallbackRate: '0.00000866',
  },
  [TONCOIN.symbol]: {
    name: 'Toncoin',
    decimals: 9,
    fallbackRate: '0.31360000',
  },
};

export const BURN_ADDRESS = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ';

export const DEFAULT_WALLET_VERSION: ApiTonWalletVersion = 'W5';
export const POPULAR_WALLET_VERSIONS: readonly ApiTonWalletVersion[] = ['v3R1', 'v3R2', 'v4R2', 'W5'];

export const DEFAULT_TIMEOUT = 10000;
export const DEFAULT_RETRIES = 3;
export const DEFAULT_ERROR_PAUSE = 500;

export const HISTORY_PERIODS: TokenPeriod[] = ['1D', '7D', '1M', '3M', '1Y', 'ALL'];

export const BROWSER_HISTORY_LIMIT = 10;

export const NFT_BATCH_SIZE = 4;
export const NOTCOIN_VOUCHERS_ADDRESS = 'EQDmkj65Ab_m0aZaW8IpKw4kYqIgITw_HRstYEkVQ6NIYCyW';
export const BURN_CHUNK_DURATION_APPROX_SEC = 30;
export const NOTCOIN_FORWARD_TON_AMOUNT = 30000000n; // 0.03 TON
export const NOTCOIN_EXCHANGERS = [
  'EQAPZauWVPUcm2hUJT9n36pxznEhl46rEn1bzBXN0RY_yiy2',
  'EQASgm0Qv3h2H2mF0W06ikPqYq2ctT3dyXMJH_svbEKKB3iZ',
  'EQArlmP-RhVIG2yAFGZyPZfM3m0YccxmpvoRi6sgRzWnAA0s',
  'EQA6pL-spYqZp1Ck6o3rpY45Cl-bvLMW_j3qdVejOkUWpLnm',
  'EQBJ_ehYjumQKbXfWUue1KHKXdTm1GuYJB0Fj2ST_DwORvpd',
  'EQBRmYSjxh9xlZpUqEmGjF5UjukI9v_Cm2kCTu4CoBn3XkOD',
  'EQBkiqncd7AFT5_23H-RoA2Vynk-Nzq_dLoeMVRthAU9RF0p',
  'EQB_OzTHXbztABe0QHgr4PtAV8T64LR6aDunXgaAoihOdxwO',
  'EQCL-x5kLg6tKVNGryItTuj6tG3FH5mhUEu0xRqQc-kbEmbe',
  'EQCZh2yJ46RaQH3AYmjEA8SMMXi77Oein4-3lvqkHseIAhD-',
  'EQChKo5IK3iNqUHUGDB9gtzjCjMTPtmsFqekuCA2MdreVEyu',
  'EQC6DNCBv076TIliRMfOt20RpbS7rNKDfSky3WrFEapFt8AH',
  'EQDE_XFZOYae_rl3ZMsgBCtRSmYhl8B4y2BZEP7oiGBDhlgy',
  'EQDddqpGA2ePXQF47A2DSL3GF6ZzIVmimfM2d16cdymy2noT',
  'EQDv0hNNAamhYltCh3pTJrq3oRB9RW2ZhEYkTP6fhj5BtZNu',
  'EQD2mP7zgO7-imUJhqYry3i07aJ_SR53DaokMupfAAobt0Xw',
] as const;

export const CLAIM_ADDRESS = 'EQB3zOTvPi1PmwdcTpqSfFKZnhi1GNKEVJM-LdoAirdLtash';
export const CLAIM_AMOUNT = 30000000n; // 0.03 TON
export const CLAIM_COMMENT = 'claim';

export const MINT_CARD_ADDRESS = 'EQBpst3ZWJ9Dqq5gE2YH-yPsFK_BqMOmgi7Z_qK6v7WbrPWv';
export const MINT_CARD_COMMENT = 'Mint card';
export const MINT_CARD_REFUND_COMMENT = 'Refund';

export const RE_LINK_TEMPLATE = /((ftp|https?):\/\/)?(?<host>(www\\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z][-a-zA-Z0-9]{1,62})\b([-a-zA-Z0-9()@:%_+.,~#?&/=]*)/g;

export const RE_TG_BOT_MENTION = /(telegram|tg)[:\s-]*@[a-z0-9_]+|(https?:\/\/)?(t\.me|telegram\.me|telegram\.dog)\/[a-z0-9_]+/mi;

export const STARS_SYMBOL = '⭐️';

export const GIVEAWAY_CHECKIN_URL = process.env.GIVEAWAY_CHECKIN_URL || 'https://giveaway.mytonwallet.io';

export const AUTOLOCK_OPTIONS_LIST = [
  {
    value: 'never',
    name: 'Disabled',
    selectedName: 'Disabled',
    period: 0,
  },
  {
    value: '1',
    name: '30 seconds',
    selectedName: 'If away for 30 sec',
    period: 30_000,
  },
  {
    value: '2',
    name: '3 minutes',
    selectedName: 'If away for 3 min',
    period: 60_000 * 3,
  },
  {
    value: '3',
    name: '10 minutes',
    selectedName: 'If away for 10 min',
    period: 60_000 * 10,
  },
] as const;

export const AUTO_CONFIRM_DURATION_MINUTES = 5;

export const PRICELESS_TOKEN_HASHES = new Set([
  '173e31eee054cb0c76f77edc7956bed766bf48a1f63bd062d87040dcd3df700f', // FIVA SY tsTON EQAxGi9Al7hamLAORroxGkvfap6knGyzI50ThkP3CLPLTtOZ
  '5226dd4e6db9af26b24d5ca822bc4053b7e08152f923932abf25030c7e38bb42', // FIVA PT tsTON EQAkxIRGXgs2vD2zjt334MBjD3mXg2GsyEZHfzuYX_trQkFL
  'fea2c08a704e5192b7f37434927170440d445b87aab865c3ea2a68abe7168204', // FIVA YT tsTON EQAcy60qg22RCq87A_qgYK8hooEgjCZ44yxhdnKYdlWIfKXL
  'e691cf9081a8aeb22ed4d94829f6626c9d822752e035800b5543c43f83d134b5', // FIVA LP tsTON EQD3BjCjxuf8mu5kvxajVbe-Ila1ScZZlAi03oS7lMmAJjM3
  '301ce25925830d713b326824e552e962925c4ff45b1e3ea21fc363a459a49b43', // FIVA SY eUSDT EQDi9blCcyT-k8iMpFMYY0t7mHVyiCB50ZsRgyUECJDuGvIl
  '02250f83fbb8624d859c2c045ac70ee2b3b959688c3d843aec773be9b36dbfc3', // FIVA PT eUSDT EQBzVrYkYPHx8D_HPfQacm1xONa4XSRxl826vHkx_laP2HOe
  'dba3adb2c917db80fd71a6a68c1fc9e12976491a8309d5910f9722efc084ce4d', // FIVA YT eUSDT EQCwUSc2qrY5rn9BfFBG9ARAHePTUvITDl97UD0zOreWzLru
  '7da9223b90984d6a144e71611a8d7c65a6298cad734faed79438dc0f7a8e53d1', // FIVA LP eUSDT EQBNlIZxIbQGQ78cXgG3VRcyl8A0kLn_6BM9kabiHHhWC4qY
  'ddf80de336d580ab3c11d194f189c362e2ca1225cae224ea921deeaba7eca818', // tsUSDe EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr
  'eb9d9891a32ec94425c09735f6ade73f4c171da0091f874d6e9d25247d583990', // Affluent TON Lending Vault EQADQ6JcK0NMuNM5uwCcS9bjcn2RTvcxYIZjNlhIhywUrfBN
  'f66c149de251ffd031bdb34b79abe43a062ba16b815433691e3ec40a77f01d71', // Affluent Ethena Multiply Vault EQDXmtbt1-WSP00tSh6N6FH-4lX7LbnrjORClmtmuZqg4Ymm
  'bca42dbdcbc0d885aaffb1eeeb027d9f338c2dd68701a05641c1d1c3171a7400', // Affluent TON Multiply Vault EQDtxQqkgIRQQR5hWlrQxiJMtLwjR3rEYNUBbEcvPDwCs1Ng
]);

export const STAKED_TOKEN_SLUGS = new Set([
  STAKED_TON_SLUG,
  STAKED_MYCOIN_SLUG,
  TON_TSUSDE.slug,
]);

export const DEFAULT_OUR_SWAP_FEE = 0.875;
export const MTW_AGGREGATOR_QUERY_ID = '4246015164496276000';

export const DEFAULT_STAKING_STATE: ApiLiquidStakingState = {
  type: 'liquid',
  id: 'liquid',
  tokenSlug: TONCOIN.slug,
  annualYield: 3.9,
  yieldType: 'APY',
  balance: 0n,
  pool: LIQUID_POOL,
  tokenBalance: 0n,
  unstakeRequestAmount: 0n,
  instantAvailable: 0n,
  start: 0,
  end: 0,
};

export const DEFAULT_NOMINATORS_STAKING_STATE: ApiNominatorsStakingState = {
  type: 'nominators',
  id: 'nominators',
  tokenSlug: TONCOIN.slug,
  annualYield: 3.9,
  yieldType: 'APY',
  balance: 0n,
  pool: 'Ef8dgIOIRyCLU0NEvF8TD6Me3wrbrkS1z3Gpjk3ppd8m8-s_',
  start: 0,
  end: 0,
};

export const SWAP_API_VERSION = 3;
export const TONCENTER_ACTIONS_VERSION = 'v1';

export const JVAULT_URL = 'https://jvault.xyz';

export const HELP_CENTER_URL = {
  home: {
    en: 'https://help.mytonwallet.io/',
    ru: 'https://help.mytonwallet.io/ru',
  },
  domainScam: {
    en: 'https://help.mytonwallet.io/intro/scams/.ton-domain-scams',
    ru: 'https://help.mytonwallet.io/ru/baza-znanii/moshennichestvo-i-skamy/moshennichestvo-s-ispolzovaniem-domenov-.ton',
  },
  seedScam: {
    en: 'https://help.mytonwallet.io/intro/scams/leaked-seed-phrases',
    ru: 'https://help.mytonwallet.io/ru/baza-znanii/moshennichestvo-i-skamy/slitye-sid-frazy',
  },
  ethenaStaking: {
    en: 'https://help.mytonwallet.io/intro/staking/what-is-usde-how-does-usde-staking-work',
    ru: 'https://help.mytonwallet.io/ru/baza-znanii/steiking/chto-takoe-usde-kak-rabotaet-steiking-usde',
  },
};

const ALL_TON_DNS_ZONES = [
  {
    suffixes: ['ton'],
    baseFormat: /^([-\da-z]+\.){0,2}[-\da-z]{4,126}$/i,
    resolver: 'EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz',
    collectionName: 'TON DNS Domains',
    isUnofficial: false,
    isRenewable: true,
    isLinkable: true,
    isTelemint: false,
  },
  {
    suffixes: ['t.me'],
    baseFormat: /^([-\da-z]+\.){0,2}[-_\da-z]{4,32}$/i,
    resolver: 'EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi',
    collectionName: 'Telegram Usernames',
    isUnofficial: false,
    isRenewable: false,
    isLinkable: true,
    isTelemint: true,
  },
  {
    suffixes: ['vip', 'ton.vip', 'vip.ton'],
    baseFormat: /^([-\da-z]+\.){0,2}[\da-z]{1,24}$/i,
    resolver: 'EQBWG4EBbPDv4Xj7xlPwzxd7hSyHMzwwLB5O6rY-0BBeaixS',
    collectionName: 'VIP DNS Domains',
    isUnofficial: true,
    isRenewable: false,
    isLinkable: true,
    isTelemint: false,
  },
  {
    suffixes: ['gram'],
    baseFormat: /^([-\da-z]+\.){0,2}[-\da-z]{1,127}$/i,
    resolver: 'EQAic3zPce496ukFDhbco28FVsKKl2WUX_iJwaL87CBxSiLQ',
    collectionName: 'GRAM DNS Domains',
    isUnofficial: true,
    isRenewable: false,
    isLinkable: true,
    isTelemint: false,
  },
] as const;

export const TON_DNS_ZONES = IS_CORE_WALLET
  ? ALL_TON_DNS_ZONES.filter(({ isUnofficial }) => !isUnofficial)
  : ALL_TON_DNS_ZONES;

export const RENEWABLE_TON_DNS_COLLECTIONS = new Set<string>(
  TON_DNS_ZONES.filter((zone) => zone.isRenewable).map((zone) => zone.resolver),
);

export const DEFAULT_AUTOLOCK_OPTION: AutolockValueType = '3';
export const WRONG_ATTEMPTS_BEFORE_LOG_OUT_SUGGESTION = 2;

export const UNKNOWN_TOKEN = {
  symbol: '[Unknown]',
  decimals: 9,
} as const;

export const PUSH_ADDRESS = 'EQBNl2Hnxgc-olNY_Qq9iB3Rd3P7GGrW2oUzLc47BW3EjHNy';

export const DEFAULT_CHAIN: ApiChain = 'ton';
