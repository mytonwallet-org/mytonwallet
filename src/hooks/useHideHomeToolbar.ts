import createHideCounter from './createHideCounter';

const homeToolbarHideCounter = createHideCounter();

// A screen with its own header and a back button takes the place of the toolbar over the tabs
export default function useHideHomeToolbar(isHidden: boolean) {
  homeToolbarHideCounter.useHide(isHidden);
}

export function useIsHomeToolbarHidden() {
  return homeToolbarHideCounter.useIsHidden();
}
