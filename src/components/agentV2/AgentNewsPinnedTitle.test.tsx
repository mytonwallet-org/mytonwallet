import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentNewsPinnedTitle from './AgentNewsPinnedTitle';

// Each class name is its own key here
jest.mock('./AgentNewsPinnedTitle.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

describe('AgentNewsPinnedTitle', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  function getCharacters(className: string) {
    return Array.from(root.querySelectorAll(`.${className}`), (element) => element.textContent).join('');
  }

  it.each([
    [2, 'rollInFromBelow', 'rollAwayAbove'],
    [0, 'rollInFromAbove', 'rollAwayBelow'],
  ])('keeps the part both days start with and rolls the rest in the way digest %i comes', async (
    digestKey, rollIn, rollAway,
  ) => {
    TeactDOM.render(<AgentNewsPinnedTitle text="November 9" digestKey={1} />, root);
    TeactDOM.render(<AgentNewsPinnedTitle text="November 10" digestKey={digestKey} />, root);
    await pause(20);

    const title = root.firstElementChild!;
    expect(title.firstChild!.textContent).toBe('November ');
    expect(getCharacters(rollIn)).toBe('10');
    expect(getCharacters(rollAway)).toBe('9');

    await pause(250);
    expect(root.innerHTML).toBe('<span class="root">November 10</span>');
  });
});
