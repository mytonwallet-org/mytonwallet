import type { VirtualElement } from '../lib/teact/teact';
import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import { pause } from '../util/schedulers';
import createHideCounter from './createHideCounter';

// Long enough for Teact to run the effects of a render
const EFFECTS_DELAY_MS = 50;

let roots: HTMLDivElement[] = [];

async function render(element: VirtualElement) {
  const root = document.createElement('div');
  roots.push(root);
  TeactDOM.render(element, root);
  await pause(EFFECTS_DELAY_MS);

  return root;
}

async function unmount(root: HTMLDivElement) {
  TeactDOM.render(undefined, root);
  await pause(EFFECTS_DELAY_MS);
}

afterEach(() => {
  roots.forEach((root) => TeactDOM.render(undefined, root));
  roots = [];
});

describe('createHideCounter', () => {
  it('stays hidden while any screen asks', async () => {
    const { useHide, useIsHidden } = createHideCounter();

    function Screen({ isHidden }: { isHidden: boolean }) {
      useHide(isHidden);

      return undefined;
    }

    function Subscriber() {
      return <div>{String(useIsHidden())}</div>;
    }

    const subscriber = await render(<Subscriber />);
    const first = await render(<Screen isHidden />);
    const second = await render(<Screen isHidden />);
    await render(<Screen isHidden={false} />);
    expect(subscriber.textContent).toBe('true');

    await unmount(first);
    expect(subscriber.textContent).toBe('true');

    await unmount(second);
    expect(subscriber.textContent).toBe('false');
  });
});
