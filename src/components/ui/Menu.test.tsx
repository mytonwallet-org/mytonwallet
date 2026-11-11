import React, { requestAfterRender } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { pause } from '../../util/schedulers';

import useFlag from '../../hooks/useFlag';

import Menu from './Menu';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));

describe('Menu', () => {
  let root: HTMLDivElement;
  let openMenu: NoneToVoidFunction;
  let onScreenEscape: jest.Mock;
  let releaseScreenEscape: NoneToVoidFunction;

  function MenuHost({ onClose }: { onClose: NoneToVoidFunction }) {
    const [isOpen, open, close] = useFlag();
    openMenu = open;

    return (
      <Menu
        isOpen={isOpen}
        shouldCleanup
        shouldSkipTransition
        onClose={() => {
          onClose();
          close();
        }}
      >
        Item
      </Menu>
    );
  }

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    onScreenEscape = jest.fn();
    releaseScreenEscape = captureKeyboardListeners({ onEsc: onScreenEscape });
  });

  afterEach(() => {
    releaseScreenEscape();
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('takes Escape from the screen underneath in the frame it appears', async () => {
    const onClose = jest.fn();

    TeactDOM.render(<MenuHost onClose={onClose} />, root);
    await pause(20);

    let isMenuVisibleOnEscape = false;
    await new Promise<void>((resolve) => {
      openMenu();
      requestAfterRender(() => {
        isMenuVisibleOnEscape = Boolean(root.querySelector('.menu-bubble'));
        pressEscape();
        resolve();
      });
    });

    expect(isMenuVisibleOnEscape).toBe(true);
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onScreenEscape).not.toHaveBeenCalled();

    await pause(20);
    pressEscape();

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onScreenEscape).toHaveBeenCalledTimes(1);
  });
});

function pressEscape() {
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
}
