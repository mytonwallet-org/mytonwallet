export const GIVEAWAYS_API_URL = process.env.GIVEAWAYS_API_URL || 'https://api.mytonwallet.org/giveaways';
export const GIVEAWAY_CAPTCHA_PUBLIC_KEY = process.env.GIVEAWAY_CAPTCHA_PUBLIC_KEY;

export const APP_ENV = process.env.APP_ENV || 'production';
export const DEBUG = APP_ENV !== 'production' && APP_ENV !== 'perf' && APP_ENV !== 'test';
export const STRICTERDOM_ENABLED = DEBUG;

export const SHORT_CURRENCY_SYMBOL_MAP = {
  USD: '$',
  EUR: '€',
  RUB: '₽',
  CNY: '¥',
};

export const ANIMATION_END_DELAY = 50;

export const ANIMATED_STICKER_TINY_SIZE_PX = 70;
export const ANIMATED_STICKER_SMALL_SIZE_PX = 110;
export const ANIMATED_STICKER_MIDDLE_SIZE_PX = 120;
export const ANIMATED_STICKER_DEFAULT_PX = 150;
export const ANIMATED_STICKER_BIG_SIZE_PX = 156;
export const ANIMATED_STICKER_HUGE_SIZE_PX = 192;

export const ANIMATION_LEVEL_MIN = 0;
export const ANIMATION_LEVEL_MED = 1;
export const ANIMATION_LEVEL_MAX = 2;
export const ANIMATION_LEVEL_DEFAULT = ANIMATION_LEVEL_MAX;

export const THEME_DEFAULT = 'system';

export const IS_CAPACITOR = false;
