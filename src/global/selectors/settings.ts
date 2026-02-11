import type { DeveloperSettingsOverrideValue, GlobalState } from '../types';

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
