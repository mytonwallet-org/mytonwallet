// Pure decision logic for the desktop auto-updater's channel gating. Kept free of electron
// imports so both the main-window wiring and the update poller can reuse it and it stays unit-tested.
// The staging guard is deliberately narrow: only a non-preview macOS staging shell has a feed to
// read (release/** builds load file:// and never self-update; win/linux staging feeds are out of
// scope), and production keeps its exact prior behavior.

export function shouldStartUpdater(
  { isProduction, isStaging, isPreview, isMacOs }:
  { isProduction: boolean; isStaging: boolean; isPreview: boolean; isMacOs: boolean },
): boolean {
  return isProduction || (isStaging && !isPreview && isMacOs);
}

export function getGateBase(
  { isStaging, betaUpdateUrl, productionUrl }:
  { isStaging: boolean; betaUpdateUrl: string; productionUrl: string },
): string {
  return isStaging ? betaUpdateUrl : productionUrl;
}
