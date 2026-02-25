// @ts-ignore Due to `NormalModuleReplacementPlugin`
import { getPlatform } from '../util/getPlatform';

export const PLATFORM_ENV = getPlatform();
export const IS_IOS = PLATFORM_ENV === 'iOS';
export const IS_ANDROID = PLATFORM_ENV === 'Android';
