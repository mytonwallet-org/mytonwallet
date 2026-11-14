import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentNewsPinnedDigest from './AgentNewsPinnedDigest';

// Each class name is its own key here
jest.mock('./AgentNewsPinnedDigest.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

const DIGESTS = [
  { title: 'November 9', text: 'Older news', deliveredAt: '2026-11-08T22:00:00.000Z' },
  { title: 'November 10', text: 'Newer news', deliveredAt: '2026-11-09T22:00:00.000Z' },
];

describe('AgentNewsPinnedDigest', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('slides in the text of a digest shown again, the way its time says', async () => {
    async function show(index: number) {
      const { title, text, deliveredAt } = DIGESTS[index];
      TeactDOM.render(
        <AgentNewsPinnedDigest
          title={title}
          text={text}
          digestKey={Date.parse(deliveredAt)}
          index={index}
          count={DIGESTS.length}
          onClick={jest.fn()}
        />,
        root,
      );
      await pause(20);
    }

    await show(1);
    await show(0);
    await show(1);

    const transition = root.querySelector('.Transition')!;
    expect(transition.querySelector('.Transition_slide-to')!.textContent).toBe('Newer news');
    expect(transition.classList.contains('Transition-slideVerticalFade')).toBe(true);
  });
});
