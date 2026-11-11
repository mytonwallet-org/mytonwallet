import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';

import AgentMessageControls from './AgentMessageControls';

let mockCanAnimate = true;

jest.mock('../agent/helpers/getCanAnimate', () => ({
  __esModule: true,
  default: () => mockCanAnimate,
}));

const LONG_FOLLOWUP_TEXT = 'How do the rewards of liquid staking accrue over the following months?';
const PLACEHOLDER_WIDTH = 230;
const FOLLOWUP_WIDTH = 180;
const LABEL_WIDTH = 150;
const PILL_HEIGHT = 38;

describe('AgentMessageControls', () => {
  let root: HTMLDivElement;
  let cancelEntrance: jest.Mock;

  beforeEach(() => {
    mockCanAnimate = true;
    cancelEntrance = jest.fn();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  it('renders suggested followups as buttons bound to their ids', async () => {
    TeactDOM.render(
      <AgentMessageControls
        followups={[{ id: 'followup-1', kind: 'suggested_prompt', text: 'How do rewards accrue?' }]}
        isDisabled={false}
        shouldShowFollowups
        onFollowup={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const followups = root.querySelectorAll('button[data-agent-followup-id]');
    expect(followups).toHaveLength(1);
    expect(followups[0].getAttribute('data-agent-followup-id')).toBe('followup-1');
    expect(followups[0].textContent).toBe('How do rewards accrue?');
  });

  it('removes the followups of an older answer from the DOM', async () => {
    const followups = [{ id: 'followup-1', kind: 'suggested_prompt' as const, text: 'How do rewards accrue?' }];
    const render = (shouldShowFollowups: boolean) => TeactDOM.render(
      <AgentMessageControls
        followups={followups}
        isDisabled={false}
        shouldShowFollowups={shouldShowFollowups}
        onFollowup={jest.fn()}
      >
        <button type="button" data-action>Open</button>
      </AgentMessageControls>,
      root,
    );

    render(false);
    await pause(20);
    expect(root.querySelector('[data-action]')).not.toBeNull();
    expect(root.querySelector('button[data-agent-followup-id]')).toBeNull();

    render(true);
    await pause(20);
    expect(root.querySelector('button[data-agent-followup-id]')).not.toBeNull();

    render(false);
    await pause(20);
    expect(root.querySelector('button[data-agent-followup-id]')).not.toBeNull();
    await pause(250);
    expect(root.querySelector('button[data-agent-followup-id]')).toBeNull();
  });

  it('removes the followups at once without motion', async () => {
    mockCanAnimate = false;
    const followups = [{ id: 'followup-1', kind: 'suggested_prompt' as const, text: 'How do rewards accrue?' }];
    const render = (shouldShowFollowups: boolean) => TeactDOM.render(
      <AgentMessageControls
        followups={followups}
        isDisabled={false}
        shouldShowFollowups={shouldShowFollowups}
        onFollowup={jest.fn()}
      >
        <button type="button" data-action>Open</button>
      </AgentMessageControls>,
      root,
    );

    render(true);
    await pause(20);
    render(false);
    await pause(20);

    expect(root.querySelector('button[data-agent-followup-id]')).toBeNull();
  });

  it('narrows a suggestion that wraps to its longest line and leaves one on a single line as it is', async () => {
    // The text of the long suggestion takes two lines, the second shorter than the first
    jest.spyOn(HTMLElement.prototype, 'getClientRects').mockImplementation(function getClientRects(this: HTMLElement) {
      const rects = this.textContent === LONG_FOLLOWUP_TEXT
        ? [new DOMRect(10, 0, 150.25, 20), new DOMRect(10, 20, 96, 20)]
        : [new DOMRect(10, 0, 80, 20)];
      return rects as unknown as DOMRectList;
    });

    TeactDOM.render(
      <AgentMessageControls
        followups={[
          { id: 'followup-1', kind: 'suggested_prompt', text: LONG_FOLLOWUP_TEXT },
          { id: 'followup-2', kind: 'suggested_prompt', text: 'Short one' },
        ]}
        isDisabled={false}
        shouldShowFollowups
        onFollowup={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const labels = root.querySelectorAll<HTMLElement>('[data-agent-followup-label]');
    expect(labels).toHaveLength(2);
    expect(labels[0].style.width).toBe('151px');
    expect(labels[1].style.width).toBe('');
  });

  it('turns a placeholder into its suggestion by resizing the pill and showing only the text and arrow', async () => {
    const { animations, restore } = mockPillAnimations();

    try {
      renderControls(undefined, true);
      await pause(20);
      const placeholders = root.querySelectorAll<HTMLElement>('[data-agent-followup-placeholder]');
      expect(placeholders).toHaveLength(3);

      // The last placeholder has come in whole
      const computedStyleSpy = jest.spyOn(window, 'getComputedStyle')
        .mockReturnValue({ opacity: '1' } as CSSStyleDeclaration);
      const revealEnd = new Event('animationend', { bubbles: true });
      Object.defineProperty(revealEnd, 'animationName', { value: 'followup-appear' });
      placeholders[2].dispatchEvent(revealEnd);
      computedStyleSpy.mockRestore();

      renderControls([{ id: 'followup-1', kind: 'suggested_prompt', text: 'How do rewards accrue?' }]);
      await pause(20);

      const button = root.querySelector<HTMLElement>('[data-agent-followup-id]')!;
      const getKeyframes = (element: Element) => animations
        .filter((animation) => animation.element === element)
        .map(({ keyframes }) => keyframes);
      expect(getKeyframes(button)).toEqual([[
        { width: `${PLACEHOLDER_WIDTH}px`, height: `${PILL_HEIGHT}px`, overflow: 'hidden' },
        { width: `${FOLLOWUP_WIDTH}px`, height: `${PILL_HEIGHT}px`, overflow: 'hidden' },
      ]]);
      // The pill shows at once, without the entrance out of a blur
      expect(cancelEntrance).toHaveBeenCalled();
      Array.from(button.children).forEach((part) => {
        expect(getKeyframes(part)).toContainEqual([{ opacity: 0 }, { opacity: 1 }]);
      });
    } finally {
      restore();
    }
  });

  it('brings the suggestions of placeholders still coming in in with their own entrance, out of a blur', async () => {
    const { animations, restore } = mockPillAnimations();

    try {
      renderControls(undefined, true);
      await pause(20);
      expect(root.querySelectorAll('[data-agent-followup-placeholder]')).toHaveLength(3);

      renderControls([{ id: 'followup-1', kind: 'suggested_prompt', text: 'How do rewards accrue?' }]);
      await pause(20);

      const button = root.querySelector<HTMLElement>('[data-agent-followup-id]')!;
      const getKeyframes = (element: Element) => animations
        .filter((animation) => animation.element === element)
        .map(({ keyframes }) => keyframes);
      expect(getKeyframes(button)).toEqual([[
        { width: `${PLACEHOLDER_WIDTH}px`, height: `${PILL_HEIGHT}px`, overflow: 'hidden' },
        { width: `${FOLLOWUP_WIDTH}px`, height: `${PILL_HEIGHT}px`, overflow: 'hidden' },
      ]]);
      expect(cancelEntrance).not.toHaveBeenCalled();
      Array.from(button.children).forEach((part) => {
        expect(getKeyframes(part)).not.toContainEqual([{ opacity: 0 }, { opacity: 1 }]);
      });
    } finally {
      restore();
    }
  });

  /** Records the pills' animations rather than playing them; each element has an entrance from its styles */
  function mockPillAnimations() {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const originalGetAnimations = Object.getOwnPropertyDescriptor(Element.prototype, 'getAnimations');
    const animations: { element: Element; keyframes: Keyframe[] }[] = [];
    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value(this: Element, keyframes: Keyframe[]) {
        animations.push({ element: this, keyframes });
        return { playState: 'finished', cancel: jest.fn() } as unknown as Animation;
      },
    });
    Object.defineProperty(Element.prototype, 'getAnimations', {
      configurable: true,
      value: () => [{ cancel: cancelEntrance }],
    });
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: HTMLElement) {
      const width = this.dataset.agentFollowupPlaceholder !== undefined
        ? PLACEHOLDER_WIDTH
        : this.dataset.agentFollowupId ? FOLLOWUP_WIDTH : LABEL_WIDTH;
      return new DOMRect(0, 0, width, PILL_HEIGHT);
    });

    return {
      animations,
      restore() {
        restoreProperty(Element.prototype, 'animate', originalAnimate);
        restoreProperty(Element.prototype, 'getAnimations', originalGetAnimations);
      },
    };
  }

  function renderControls(followups?: AgentPublicFollowUpV2[], isLoadingFollowups = false) {
    TeactDOM.render(
      <AgentMessageControls
        followups={followups}
        isLoadingFollowups={isLoadingFollowups}
        isDisabled={false}
        shouldShowFollowups
        onFollowup={jest.fn()}
      />,
      root,
    );
  }
});

function restoreProperty(object: object, property: string, descriptor?: PropertyDescriptor) {
  if (descriptor) {
    Object.defineProperty(object, property, descriptor);
  } else {
    Reflect.deleteProperty(object, property);
  }
}
