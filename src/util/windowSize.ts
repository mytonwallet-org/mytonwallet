import { IS_CAPACITOR, IS_TELEGRAM_APP } from '../config';
import { requestMutation } from '../lib/fasterdom/fasterdom';
import { applyStyles } from './animation';
import { SECOND } from './dateFormat';
import safeExec from './safeExec';
import { throttle } from './schedulers';
import { IS_ANDROID, IS_IOS } from './windowEnvironment';

const WINDOW_RESIZE_THROTTLE_MS = IS_TELEGRAM_APP ? 25 : 250;
const WINDOW_ORIENTATION_CHANGE_THROTTLE_MS = IS_IOS ? 350 : 250;
const SAFE_AREA_INITIALIZATION_DELAY = SECOND;

const { documentElement } = document;
const initialHeight = window.innerHeight;
const virtualKeyboardOpenListeners: NoneToVoidFunction[] = [];

let currentWindowSize = updateSizes();

window.addEventListener('orientationchange', throttle(() => {
  currentWindowSize = updateSizes();
}, WINDOW_ORIENTATION_CHANGE_THROTTLE_MS, false));

if (!IS_IOS) {
  window.addEventListener('resize', throttle(() => {
    currentWindowSize = updateSizes();
  }, WINDOW_RESIZE_THROTTLE_MS, true));
}

if (IS_CAPACITOR) {
  void import('@capacitor/keyboard')
    .then(({ Keyboard }) => {
      void Keyboard.addListener('keyboardWillShow', () => {
        documentElement.classList.add('is-keyboard-open');
      });

      void Keyboard.addListener('keyboardDidShow', async (info) => {
        // Due to a bug in Android, extra space is added to the bottom of the screen when the keyboard is opened only on iOS
        // https://capacitorjs.com/docs/apis/keyboard#configuration (resizeOnFullScreen)
        if (IS_IOS) {
          await adjustBodyPaddingForKeyboard(info.keyboardHeight);
        }

        for (const cb of virtualKeyboardOpenListeners) {
          safeExec(cb);
        }
      });

      void Keyboard.addListener('keyboardWillHide', () => {
        documentElement.classList.remove('is-keyboard-open');

        if (IS_IOS) {
          void adjustBodyPaddingForKeyboard(0);
        }
      });
    });
}

if ('visualViewport' in window && (IS_IOS || IS_ANDROID)) {
  window.visualViewport!.addEventListener('resize', throttle((e: Event) => {
    const target = e.target as VisualViewport;

    patchVh();
    currentWindowSize = {
      ...getWindowSize(),
      height: target.height,
    };
  }, WINDOW_RESIZE_THROTTLE_MS, true));
}

export function updateSizes() {
  patchVh();
  patchSafeAreaProperty();

  return getWindowSize();
}

function getWindowSize() {
  return {
    width: window.innerWidth,
    height: window.innerHeight,
    screenHeight: window.screen.height,
    safeAreaTop: getSafeAreaTop(),
    safeAreaBottom: getSafeAreaBottom(),
  };
}

export default {
  get: () => currentWindowSize,
  getIsKeyboardVisible: () => initialHeight > currentWindowSize.height,
};

// Registers a callback that will be fired each time the virtual keyboard is opened and the <body> size is adjusted
export function onVirtualKeyboardOpen(cb: NoneToVoidFunction) {
  virtualKeyboardOpenListeners.push(cb);
}

function patchVh() {
  if (!(IS_IOS || IS_ANDROID) || IS_CAPACITOR || (IS_IOS && IS_TELEGRAM_APP)) return;

  const height = window.innerHeight;

  requestMutation(() => {
    document.documentElement.style.setProperty('--vh', IS_IOS ? '1dvh' : `${height * 0.01}px`);
  });
}

function adjustBodyPaddingForKeyboard(keyboardHeight: number) {
  return new Promise<void>((resolve) => {
    requestMutation(() => {
      applyStyles(document.body, { paddingBottom: keyboardHeight ? `${keyboardHeight}px` : '' });
      resolve();
    });
  });
}

function patchSafeAreaProperty() {
  toggleSafeAreaClasses();

  // WebKit has issues with this property on page load
  // https://bugs.webkit.org/show_bug.cgi?id=191872
  setTimeout(() => {
    toggleSafeAreaClasses();
    updateSafeAreaValues();
  }, SAFE_AREA_INITIALIZATION_DELAY);
}

function getSafeAreaTop() {
  const value = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--safe-area-top-value'), 10);

  return Number.isNaN(value) ? 0 : value;
}

function getSafeAreaBottom() {
  const value = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--safe-area-bottom-value'), 10);

  return Number.isNaN(value) ? 0 : value;
}

function toggleSafeAreaClasses() {
  const { safeAreaTop, safeAreaBottom } = getWindowSize();
  const { documentElement } = document;

  requestMutation(() => {
    documentElement.classList.toggle('with-safe-area-top', !Number.isNaN(safeAreaTop) && safeAreaTop > 0);
    documentElement.classList.toggle('with-safe-area-bottom', !Number.isNaN(safeAreaBottom) && safeAreaBottom > 0);
  });
}

function updateSafeAreaValues() {
  const { safeAreaTop, safeAreaBottom } = getWindowSize();

  currentWindowSize = {
    ...currentWindowSize,
    safeAreaTop,
    safeAreaBottom,
  };
}
