import createHideCounter from './createHideCounter';

const bottomBarHideCounter = createHideCounter();

// Use this hook when you need to temporarily hide the bottom bar on a screen, for example,
// when assumes the use of the entire screen height - `PasswordForm` with biometrics
export default function useHideBottomBar(isHidden: boolean) {
  bottomBarHideCounter.useHide(isHidden);
}

export function useIsBottomBarHidden() {
  return bottomBarHideCounter.useIsHidden();
}
