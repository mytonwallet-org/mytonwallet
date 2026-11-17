import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import AgentNewsPinnedTitle from './AgentNewsPinnedTitle';

// Each class name is its own key here
jest.mock('./AgentNewsPinnedTitle.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

// The component's `ROLL_DURATION`
const ROLL_DURATION = 200;
// Above the 35 ms timeout fallback of `fastRaf`, which runs Teact's scheduled update pass
const RENDER_FLUSH_TIME = 36;

describe('AgentNewsPinnedTitle', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(RENDER_FLUSH_TIME);
    root.remove();
    jest.useRealTimers();
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
    await jest.advanceTimersByTimeAsync(RENDER_FLUSH_TIME);

    const title = root.firstElementChild!;
    expect(title.firstChild!.textContent).toBe('November ');
    expect(getCharacters(rollIn)).toBe('10');
    expect(getCharacters(rollAway)).toBe('9');

    await jest.advanceTimersByTimeAsync(ROLL_DURATION + RENDER_FLUSH_TIME);
    expect(root.innerHTML).toBe('<span class="root">November 10</span>');
  });
});
