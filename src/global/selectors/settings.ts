import type { DeveloperSettingsOverrideValue, GlobalState } from '../types';

import { ANIMATION_LEVEL_MIN } from '../../config';

function selectOverriddenValue<Value>(
  originalValue: Value | undefined,
  overrideValue: DeveloperSettingsOverrideValue<Value> | undefined,
) {
  if (overrideValue === undefined) {
    return originalValue;
  }

  if (overrideValue === '__undefined') {
    return undefined;
  }

  return overrideValue;
}

export function selectDeveloperSettingsOverrides(global: GlobalState) {
  return global.settings.developerSettingsOverrides;
}

export function selectSeasonalThemeOverride(global: GlobalState) {
  return selectDeveloperSettingsOverrides(global)?.seasonalTheme;
}

export function selectSeasonalTheme(global: GlobalState) {
  return selectOverriddenValue(global.seasonalTheme, selectSeasonalThemeOverride(global));
}

/**
 * The 3D card is a motion effect, so it obeys the global animation switch as well as its own
 * setting. A user who turned animations off does not expect the card to keep moving.
 */
export function selectIs3dCardDisabled(global: GlobalState) {
  return Boolean(global.settings.is3dCardDisabled)
    || global.settings.animationLevel === ANIMATION_LEVEL_MIN;
}
