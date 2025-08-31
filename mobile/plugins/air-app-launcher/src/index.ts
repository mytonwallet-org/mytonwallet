import { registerPlugin } from '@capacitor/core';

import type { AirAppLauncherPlugin } from './definitions';

const AirAppLauncher = registerPlugin<AirAppLauncherPlugin>('AirAppLauncher');

export * from './definitions';
export { AirAppLauncher };
