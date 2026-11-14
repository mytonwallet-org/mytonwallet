import '../../global/actions/ui/misc';

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';
import * as globalState from '../../global';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage, ToastType } from '../../global/types';

import * as haptics from '../../util/haptics';
import { getTranslation } from '../../util/langProvider';
import { pause } from '../../util/schedulers';
import { AGENT_FEEDBACK_ANIMATIONS, getAgentFeedbackParabolaPoint } from './agentFeedback';
import { getIsAgentFeedbackFlying } from './agentFeedbackFlight';

import { CLOSE_DURATION } from '../../hooks/useShowTransition';

import MessageBubble from '../agent/MessageBubble';
import AgentFeedbackPill from './AgentFeedbackPill';

jest.mock('../../hooks/useLang', () => {
  const lang = Object.assign((key: string) => key, { code: 'en', isRtl: false });
  return {
    __esModule: true,
    default: () => lang,
    LangProvider: ({ children }: { children: unknown }) => children,
    useLangForCode: () => lang,
    mockLang: lang,
  };
});
// Styles and pictures share one stub here. Its class names are their own keys, so that the motion shows in them, and
// it turns into a stub URL as a picture's source.
jest.mock('./AgentFeedbackBadge.module.scss', () => new Proxy({}, {
  get: (target, key) => {
    if (key === '__esModule') return false;
    if (key === Symbol.toPrimitive) return () => 'test-file-stub';
    return key;
  },
}));

// Each drawing of an emoji has a name of its own here, which shows which one is drawn
jest.mock('./agentFeedback', () => {
  const actual = jest.requireActual('./agentFeedback');
  const animations = Object.fromEntries(Object.entries(actual.AGENT_FEEDBACK_ANIMATIONS).map(([reaction, value]) => [
    reaction,
    {
      ...(value as object),
      still: `${reaction}-still.png`,
      rest: `${reaction}-rest.png`,
      start: `${reaction}-start.png`,
    },
  ]));

  return { ...actual, AGENT_FEEDBACK_ANIMATIONS: animations };
});

// Telegram's animations draw nothing here. Each stands for itself with its name and size, loads at once, and ends
// when a test ends it.
jest.mock('../ui/AnimatedSticker', () => {
  const { createElement, useEffect } = jest.requireActual('../../lib/teact/teact');
  const endings = new Map<string, NoneToVoidFunction | undefined>();

  function MockAnimatedSticker({
    renderId, size, play, className, onLoad, onEnded,
  }: {
    renderId: string;
    size: number;
    play?: boolean | string;
    className?: string;
    onLoad?: NoneToVoidFunction;
    onEnded?: NoneToVoidFunction;
  }) {
    endings.set(renderId, onEnded);
    useEffect(() => {
      onLoad?.();
    }, [onLoad]);

    return createElement('div', {
      className, 'data-sticker': renderId, 'data-size': String(size), 'data-play': play ? String(play) : 'false',
    });
  }

  return {
    __esModule: true,
    default: MockAnimatedSticker,
    endMockSticker: (renderId: string) => endings.get(renderId)?.(),
  };
});

const { endMockSticker } = jest.requireMock<{ endMockSticker: (renderId: string) => void }>('../ui/AnimatedSticker');
const { mockLang } = jest.requireMock<{ mockLang: { isRtl: boolean } }>('../../hooks/useLang');

// Frames run on their timeout fallback here
const WAIT_DURATION = 2000;
const WAIT_INTERVAL = 50;
const FLIGHT_SELECTOR = '[data-agent-feedback-flight]';
const AWAITING_ATTRIBUTE = 'data-agent-feedback-awaiting';
const MESSAGE_ID = 2;
// The design's lifted answer, which jsdom does not lay out
const BUBBLE_RECT = {
  x: 16, y: 219, left: 16, right: 343, top: 219, bottom: 446, width: 327, height: 227, toJSON: () => undefined,
};
// The 22 px emoji's frame at the bubble's bottom trailing corner: centred 3 px inside its trailing edge, 3 px under its
// bottom
const CORNER_FRAME = 'translate3d(329px, 427px, 0)';
// The like icon's place in the design's cloud, which the flight starts from
const LIKE_ICON_CENTER = { x: 312, y: 185 };
const CORNER_CENTER = { x: 340, y: 438 };
const LIKED_TOAST = getTranslation('$agent_feedback_liked_toast');
const DISLIKED_TOAST = getTranslation('$agent_feedback_disliked_toast');
const SUPPORT_LIKED_TOAST = getTranslation('$agent_feedback_support_liked_toast');
const SUPPORT_DISLIKED_TOAST = getTranslation('$agent_feedback_support_disliked_toast');

const flightObservers: MutationObserver[] = [];
const partRecordings: { stop: () => string[] }[] = [];
// The toasts the app was asked to show, which the wallet's `showToast` would show
const shownToasts: ToastType[] = [];

globalState.addActionHandler('showToast', (global, actions, toast) => {
  shownToasts.push(toast);
});

describe('the reaction to an answer', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;
  let initialGlobal: ReturnType<typeof globalState.getGlobal>;

  beforeEach(() => {
    initialGlobal = globalState.getGlobal();
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue(BUBBLE_RECT);
  });

  afterEach(() => {
    removeEffects();
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    flightObservers.forEach((observer) => observer.disconnect());
    flightObservers.length = 0;
    partRecordings.forEach((recording) => recording.stop());
    partRecordings.length = 0;
    globalState.setGlobal(initialGlobal);
    mockLang.isRtl = false;
    jest.restoreAllMocks();
  });

  it('shows at once on an answer rated before the chat opened, as its emoji alone, told with the bubble', async () => {
    TeactDOM.render(
      <>
        {renderAnswer(1, 'like')}
        {renderAnswer(2)}
      </>,
      root,
    );
    await pause(20);

    const badge = root.querySelector<HTMLElement>('[data-agent-v2-message-id="1"] [data-agent-feedback-badge]')!;
    expect(badge.dataset.agentFeedbackBadge).toBe('like');
    expect(badge.getAttribute('aria-hidden')).toBe('true');
    // The emoji alone, with no chip behind it, at rest
    expect(Array.from(badge.children).map(({ className }) => className)).toEqual(['icon']);
    expect(badge.querySelector('img')!.getAttribute('src')).toBe('like-rest.png');
    expect(badge.parentElement!.querySelector('.visually-hidden')!.textContent).toBe('Liked');

    // It takes no room: the rated answer's row is laid out as the other one's
    expect(root.querySelector('[data-agent-v2-message-id="2"] [data-agent-feedback-badge]')).toBeNull();
    expect(getWrapperClassName(root, 1)).toBe(getWrapperClassName(root, 2));
  });

  it('opens the answer\'s menu with its reactions on a tap', async () => {
    TeactDOM.render(renderAnswer(1, 'dislike'), root);
    await pause(20);

    root.querySelector('[data-agent-feedback-badge]')!
      .dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 340, clientY: 438 }));
    await pause(50);

    expect(getCloudButtons().map((button) => [button.getAttribute('aria-label'), button.getAttribute('aria-pressed')]))
      .toEqual([['Like', 'false'], ['Dislike', 'true']]);
  });

  it('keeps the emoji on the answer while the menu opens and closes, with nothing flying', async () => {
    const onRate = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    await pause(20);

    const opening = recordVisibleParts(root, 'like');
    dispatchMenuOpen(root);
    expect(await waitFor(() => getSticker('agent-reaction-like-appear-36')?.dataset.play === 'true')).toBe(true);

    // The cloud grows as over an answer without a reaction, its heart appearing with its circle
    expect(opening.stop()).toEqual(['badge', 'badge + cloud']);
    const [like, dislike] = getCloudButtons();
    expect(like.classList.contains('selected')).toBe(true);
    expect(dislike.classList.contains('selected')).toBe(false);
    expect(await waitFor(() => getSticker('agent-reaction-dislike-appear-36')?.dataset.play === 'true')).toBe(true);

    const closing = recordVisibleParts(root, 'like');
    closeMenu();
    expect(await waitFor(() => !document.querySelector('[data-agent-feedback-cloud]'))).toBe(true);

    expect(closing.stop()).toEqual(['badge + cloud', 'badge']);
    expect(onRate).not.toHaveBeenCalled();
    // The emoji stays at rest, with no emoji playing and no burst
    await pause(300);
    expect(getBadge(root).querySelector('img')!.getAttribute('src')).toBe('like-rest.png');
    expect(getBadge(root).className).toBe('root');
    expect(root.querySelector('[data-sticker]')).toBeNull();
    expect(document.querySelector('[data-agent-feedback-effect]')).toBeNull();
  });

  it('ignores a double click before rendering and while the chosen reaction closes the cloud', async () => {
    const onRate = jest.fn().mockResolvedValue(() => true);
    const vibrate = jest.spyOn(haptics, 'vibrate');
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);
    vibrate.mockClear();

    const like = getCloudButtons()[0];
    like.click();
    like.click();
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => document.querySelector('[data-agent-feedback-cloud]')?.classList.contains('closing'), 1))
      .toBe(true);
    like.click();
    expect(await waitFor(() => !document.querySelector('[data-agent-feedback-cloud]'))).toBe(true);

    expect(onRate.mock.calls).toEqual([[1, 'like']]);
    expect(vibrate).toHaveBeenCalledTimes(1);
    expect(getBadge(root).dataset.agentFeedbackBadge).toBe('like');
  });

  it('flies a chosen reaction to the corner on Telegram\'s parabola, where the emoji shows as it lands', async () => {
    const onRate = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    // The design's place for the cloud over its lifted answer
    const cloud = document.querySelector<HTMLElement>('[data-agent-feedback-cloud]')!;
    expect([getCloudLeft(cloud), getCloudTop(cloud)]).toEqual(['282px', '157px']);
    mockLayout();

    const starts = recordFlightStarts();
    const parts = recordVisibleParts(root, 'like');
    getCloudButtons()[0].click();
    expect(onRate).toHaveBeenCalledWith(1, 'like');
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    const frames = await recordFlight();

    // The heart leaves its place in the cloud for the flying emoji, which hands over to the corner's in the frame it
    // lands
    expect(parts.stop()).toEqual(['cloud', 'flight', 'badge']);
    // It starts as the cloud's still at the heart's place, and lands at the corner's size, as the corner's first
    // drawing, after a rise over its start
    expect(starts[0]).toEqual({
      frame: ['translate3d(294px, 167px, 0)', '36px'],
      drawings: [['like-still.png', '1'], ['like-start.png', '0']],
    });
    expect(frames.length).toBeGreaterThan(2);
    expect(frames.at(-1)!.frame).toEqual([CORNER_FRAME, '22px']);
    expect(frames.some(({ center }) => center.y < LIKE_ICON_CENTER.y)).toBe(true);
    frames.forEach(({ center, size, drawings }) => {
      const progress = (center.x - LIKE_ICON_CENTER.x) / (CORNER_CENTER.x - LIKE_ICON_CENTER.x);
      expect(center.y).toBeCloseTo(getAgentFeedbackParabolaPoint(LIKE_ICON_CENTER, CORNER_CENTER, 30, progress).y, 1);
      expect(size).toBeCloseTo(36 + (22 - 36) * progress, 1);
      // The corner's drawing covers the still over the first half, and the still goes under it after
      expect(drawings[0]).toBeCloseTo(Math.min(1, (1 - progress) * 2), 2);
      expect(drawings[1]).toBeCloseTo(Math.min(1, progress * 2), 2);
    });

    // The burst plays around the corner, and the emoji plays `center` from its first frame
    expect(await waitFor(() => Boolean(getSticker('agent-reaction-like-burst')))).toBe(true);
    expectSticker('agent-reaction-like-burst', 132);
    expect(await waitFor(() => getEffectFrame('agent-reaction-like-burst') === 'translate3d(274px, 372px, 0)'))
      .toBe(true);
    expect(await waitFor(() => Boolean(getSticker('agent-reaction-like-center-40')))).toBe(true);
    expectSticker('agent-reaction-like-center-40', 40);
    expect(await waitFor(() => getBadge(root).querySelector('img')!.classList.contains('iconHidden'))).toBe(true);
    expect(getBadge(root).querySelector('img')!.classList.contains('iconAppearing')).toBe(false);

    // Each goes when it ends, and the emoji rests on its last frame
    endMockSticker('agent-reaction-like-burst');
    expect(await waitFor(() => !document.querySelector('[data-agent-feedback-effect]'))).toBe(true);
    endMockSticker('agent-reaction-like-center-40');
    expect(await waitFor(() => !getSticker('agent-reaction-like-center-40'))).toBe(true);
    expect(getBadge(root).querySelector('img')!.className).toBe('icon');
    expect(getBadge(root).querySelector('img')!.getAttribute('src')).toBe('like-rest.png');
    expect(getWrapperClassName(root, 1)).toBe('wrapper');
  });

  it('closes the cloud into its tail as the chosen emoji leaves, and starts the burst during the flight', async () => {
    TeactDOM.render(renderAnswer(1), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[1].click();
    TeactDOM.render(renderAnswer(1, 'dislike'), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);

    // The broken heart leaves its place, while the cloud closes into its tail with the heart, as without a reaction
    const cloud = document.querySelector<HTMLElement>('[data-agent-feedback-cloud]')!;
    expect(await waitFor(() => cloud.classList.contains('closing'), 1)).toBe(true);
    expect(getCloudButtons()[1].querySelector('.icon')!.classList.contains('iconFlown')).toBe(true);
    expect(getCloudButtons()[0].querySelector('.icon')!.classList.contains('iconFlown')).toBe(false);
    // The corner's emoji waits for it out of sight, at the first frame of its animation
    expect(await waitFor(() => getIsAwaiting(findBadge(root)))).toBe(true);
    expect(getBadge(root).querySelector('img')!.getAttribute('src')).toBe('dislike-start.png');

    // The burst starts before the emoji lands
    expect(await waitFor(() => Boolean(document.querySelector('[data-agent-feedback-effect$="-burst"]')), 1))
      .toBe(true);
    expect(getFlight()).not.toBeUndefined();
    expect(await waitFor(() => !getFlight(), 1)).toBe(true);
    expect(getIsAwaiting(getBadge(root))).toBe(false);
  });

  it('keeps the emoji of the answer\'s old reaction until the new one lands, and swaps them there', async () => {
    TeactDOM.render(renderAnswer(1, 'like'), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[1].click();
    TeactDOM.render(renderAnswer(1, 'dislike'), root);
    expect(await waitFor(() => getIsAwaiting(getBadge(root)), 1)).toBe(true);

    // The heart shows while the broken heart flies
    const badge = getBadge(root);
    expect(getFlight()).not.toBeUndefined();
    expect(badge.dataset.agentFeedbackBadge).toBe('dislike');
    const replaced = badge.querySelector<HTMLImageElement>('.replacedIcon')!;
    expect(replaced.getAttribute('src')).toBe('like-rest.png');
    expect(replaced.hasAttribute(AWAITING_ATTRIBUTE)).toBe(true);
    expect(root.querySelector('.visually-hidden')!.textContent).toBe('Disliked');

    // In the frame the broken heart lands, the corner shows it and the heart goes, in 0.12 s
    expect(await waitFor(() => !getFlight(), 1)).toBe(true);
    expect(getIsAwaiting(badge)).toBe(false);
    expect(replaced.hasAttribute(AWAITING_ATTRIBUTE)).toBe(false);
    expect(replaced.isConnected).toBe(true);
    expect(await waitFor(() => !badge.querySelector('.replacedIcon'))).toBe(true);
    expect(getBadge(root)).toBe(badge);
  });

  it('follows the answer as it moves, and lands at its corner wherever it is', async () => {
    TeactDOM.render(renderAnswer(1), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    TeactDOM.render(renderAnswer(1, 'like'), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    // The answer goes back down as the menu closes
    mockBubbleRect({ top: 400, bottom: 627 });

    const frames = await recordFlight();
    expect(frames.at(-1)!.frame).toEqual(['translate3d(329px, 608px, 0)', '22px']);
  });

  it('lands at the bubble\'s left corner in a right-to-left language', async () => {
    mockLang.isRtl = true;
    TeactDOM.render(renderAnswer(1), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    TeactDOM.render(renderAnswer(1, 'like'), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);

    const frames = await recordFlight();
    expect(frames.at(-1)!.frame).toEqual(['translate3d(8px, 427px, 0)', '22px']);
  });

  it('shrinks the emoji away as its reaction is withdrawn in the cloud, with nothing flying', async () => {
    const onRate = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    expect(onRate).toHaveBeenCalledWith(1, undefined);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    expect(await waitFor(() => findBadge(root)?.classList.contains('leaving'))).toBe(true);
    expect(getFlight()).toBeUndefined();

    expect(await waitFor(() => !root.querySelector('[data-agent-feedback-badge]'))).toBe(true);
    expect(getFlight()).toBeUndefined();
    expect(document.querySelector('[data-agent-feedback-effect]')).toBeNull();
  });

  it('swaps the emoji in place for a rating changed outside the cloud, and shrinks it when withdrawn', async () => {
    TeactDOM.render(renderAnswer(1, 'like'), root);
    await pause(20);

    TeactDOM.render(renderAnswer(1, 'dislike'), root);
    expect(await waitFor(() => Boolean(root.querySelector('[data-agent-feedback-badge="dislike"]')), 1)).toBe(true);
    expect(getBadge(root).querySelector('.icon')!.classList.contains('iconAppearing')).toBe(true);
    expect(getBadge(root).querySelector('.replacedIcon')!.getAttribute('src')).toBe('like-rest.png');
    expect(getIsAwaiting(getBadge(root))).toBe(false);
    expect(root.querySelector('.visually-hidden')!.textContent).toBe('Disliked');
    expect(await waitFor(() => !root.querySelector('.replacedIcon, .iconAppearing'))).toBe(true);

    TeactDOM.render(renderAnswer(1), root);
    expect(await waitFor(() => Boolean(root.querySelector('[data-agent-feedback-badge].leaving')))).toBe(true);
    expect(await waitFor(() => !root.querySelector('[data-agent-feedback-badge]'))).toBe(true);
    expect(getFlight()).toBeUndefined();
  });

  it('fades the emoji in place, with nothing flying and no burst, where motion is off', async () => {
    const global = globalState.getGlobal();
    globalState.setGlobal({ ...global, settings: { ...global.settings, animationLevel: 0 } });
    const onRate = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    expect(document.querySelectorAll('[data-agent-feedback-cloud] .still')).toHaveLength(2);
    expect(document.querySelector('[data-sticker]')).toBeNull();

    getCloudButtons()[1].click();
    expect(onRate).toHaveBeenCalledWith(1, 'dislike');
    TeactDOM.render(renderAnswer(1, 'dislike', onRate), root);
    expect(await waitFor(() => Boolean(root.querySelector('[data-agent-feedback-badge="dislike"]')), 1)).toBe(true);

    // With reduced motion, `iconAppearing` only fades the emoji in
    expect(getBadge(root).querySelector('.icon')!.classList.contains('iconAppearing')).toBe(true);
    expect(getIsAwaiting(getBadge(root))).toBe(false);
    expect(getIsAgentFeedbackFlying(1)).toBe(false);
    await pause(500);
    expect(document.querySelector(`[data-sticker], [data-agent-feedback-effect], ${FLIGHT_SELECTOR}`)).toBeNull();
    expect(getBadge(root).querySelector('img')!.getAttribute('src')).toBe('dislike-rest.png');
  });

  it('gives the corner the rating that changed while the menu was open once the menu closes', async () => {
    TeactDOM.render(renderAnswer(1, 'like'), root);
    await pause(20);
    await openMenu(root);

    // A request that failed takes the rating back
    TeactDOM.render(renderAnswer(1), root);
    await pause(200);
    expect(getBadge(root).dataset.agentFeedbackBadge).toBe('like');
    expect(getBadge(root).className).toBe('root');

    closeMenu();
    expect(await waitFor(() => findBadge(root)?.classList.contains('leaving'))).toBe(true);
    expect(await waitFor(() => !root.querySelector('[data-agent-feedback-badge]'))).toBe(true);
  });

  it('follows the answer under the open menu, at the top of the screen while its top is out of sight', async () => {
    TeactDOM.render(renderAnswer(1), root);
    await pause(20);
    await openMenu(root);

    const cloud = document.querySelector<HTMLElement>('[data-agent-feedback-cloud]')!;
    expect(getCloudTop(cloud)).toBe('157px');

    // The list moves a long answer under the menu: its top goes out of sight, then comes down
    mockBubbleRect({ top: -600, bottom: 1400 });
    root.dispatchEvent(new Event('scroll'));
    expect(await waitFor(() => getCloudTop(cloud) === '12px')).toBe(true);

    mockBubbleRect({ top: 100, bottom: 2100 });
    root.dispatchEvent(new Event('scroll'));
    expect(await waitFor(() => getCloudTop(cloud) === `${100 - 6 - 56}px`)).toBe(true);
    // The tail keeps its offsets from the capsule
    expect(cloud.style.getPropertyValue('--large-dot-top')).toBe('48px');
    expect(cloud.style.getPropertyValue('--small-dot-top')).toBe('66px');
  });

  it('draws the cloud\'s reactions with Telegram\'s emoji, which appear in turn and play on hover', async () => {
    TeactDOM.render(renderAnswer(1), root);
    await pause(20);
    await openMenu(root);

    // Each waits for the growing capsule, the broken heart nearer the tail first
    expectSticker('agent-reaction-like-appear-36', 36, 'false');
    expect(await waitFor(() => getSticker('agent-reaction-dislike-appear-36')?.dataset.play === 'true')).toBe(true);
    expect(await waitFor(() => getSticker('agent-reaction-like-appear-36')?.dataset.play === 'true')).toBe(true);
    expect(document.querySelector('[data-agent-feedback-cloud] .still')).toBeNull();

    // It rests on the first frame of `select`, which plays once on hover
    endMockSticker('agent-reaction-like-appear-36');
    expect(await waitFor(() => !getSticker('agent-reaction-like-appear-36'))).toBe(true);
    expectSticker('agent-reaction-like-select-36', 36, 'false');
    getCloudButtons()[0].dispatchEvent(new MouseEvent('mouseenter'));
    expect(await waitFor(() => getSticker('agent-reaction-like-select-36')!.dataset.play !== 'false')).toBe(true);
    // A hover before the icon has appeared does not play it
    getCloudButtons()[1].dispatchEvent(new MouseEvent('mouseenter'));
    await pause(50);
    endMockSticker('agent-reaction-dislike-appear-36');
    expect(await waitFor(() => Boolean(getSticker('agent-reaction-dislike-select-36')))).toBe(true);
    expect(getSticker('agent-reaction-dislike-select-36')!.dataset.play).toBe('false');
  });

  it('chooses a reaction as a press on it ends, however long it was held, as a click does', async () => {
    const onRate = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);
    const [like, dislike] = getCloudButtons();

    // A press that ends elsewhere chooses nothing
    dispatchPointer(like, 'pointerdown');
    dispatchPointer(dislike, 'pointerup');
    expect(onRate).not.toHaveBeenCalled();

    // A long press grows nothing and chooses as it ends, and the click that follows it is the same press
    dispatchPointer(like, 'pointerdown');
    await pause(800);
    expect(onRate).not.toHaveBeenCalled();
    expect(getFlight()).toBeUndefined();
    expect(like.className).toBe('button like');
    expect(like.querySelector('.icon')!.className).toBe('icon');
    dispatchPointer(like, 'pointerup');
    like.click();
    expect(onRate.mock.calls).toEqual([[1, 'like']]);
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    expect(await waitFor(() => !getFlight())).toBe(true);
    expect(Array.from(document.querySelectorAll('[data-agent-feedback-effect]'))
      .every((effect) => effect.getAttribute('data-agent-feedback-effect')!.endsWith('-burst'))).toBe(true);
  });
});

describe('the cloud opened again over a reaction on its way to the corner', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;
  let bubble: HTMLDivElement;

  function getBubble() {
    return bubble;
  }

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
    // The answer, with its emoji waiting for the reaction flying to it
    bubble = document.createElement('div');
    bubble.innerHTML = `<span data-agent-feedback-badge="like"><img class="icon" ${AWAITING_ATTRIBUTE}></span>`;
    document.body.appendChild(bubble);
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue(BUBBLE_RECT);
  });

  afterEach(() => {
    removeEffects();
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    bubble.remove();
    jest.restoreAllMocks();
  });

  it('lands the flying emoji at once, showing the corner\'s', async () => {
    const onChange = jest.fn().mockResolvedValue(() => true);
    TeactDOM.render(renderCloud(true, getBubble, { onChange }), root);
    await pause(50);

    getCloudButtons()[0].click();
    expect(onChange).toHaveBeenCalledWith('like');
    TeactDOM.render(renderCloud(false, getBubble, { feedback: 'like', onChange }), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    expect(getIsAgentFeedbackFlying(MESSAGE_ID)).toBe(true);

    TeactDOM.render(renderCloud(true, getBubble, { feedback: 'like', onChange }), root);
    expect(getFlight()).toBeUndefined();
    expect(getIsAgentFeedbackFlying(MESSAGE_ID)).toBe(false);
    expect(bubble.querySelector(`[${AWAITING_ATTRIBUTE}]`)).toBeNull();
    // The heart's place in the cloud opened again has it back
    expect(getCloudButtons()[0].querySelector('.icon')!.classList.contains('iconFlown')).toBe(false);
  });
});

describe('the toast explaining a first reaction', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;
  let initialGlobal: ReturnType<typeof globalState.getGlobal>;

  beforeEach(() => {
    initialGlobal = globalState.getGlobal();
    setShownToasts(undefined);
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue(BUBBLE_RECT);
  });

  afterEach(() => {
    removeEffects();
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    globalState.setGlobal(initialGlobal);
    jest.restoreAllMocks();
  });

  it.each([true, false])('explains the first like after saving and landing (save first: %s)', async (isSaveFirst) => {
    let confirmSave: (value: () => boolean) => void;
    const confirmation = new Promise<() => boolean>((resolve) => {
      confirmSave = resolve;
    });
    const onRate = jest.fn().mockReturnValue(confirmation);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    expect(getToasts()).toEqual([]);
    if (isSaveFirst) {
      confirmSave!(() => true);
      await pause(20);
      expect(getIsAgentFeedbackFlying(1)).toBe(true);
      expect(getToasts()).toEqual([]);
      expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
    }
    expect(await waitFor(() => !getIsAgentFeedbackFlying(1), 1)).toBe(true);
    if (!isSaveFirst) {
      expect(getToasts()).toEqual([]);
      expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
      confirmSave!(() => true);
    }
    expect(await waitFor(() => getToasts().length > 0, 1)).toBe(true);
    expect(getToasts()).toEqual([LIKED_TOAST]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toEqual({ like: true });
    // Its icon's place plays the heart's `center` once more, and rests on its last frame
    const { tgsUrl: likeTgsUrl, ...likeIcon } = shownToasts[0].animatedIcon!;
    expect(likeTgsUrl).toBe(AGENT_FEEDBACK_ANIMATIONS.like.center);
    expect(likeIcon).toEqual({ previewUrl: 'like-rest.png', size: 40 });

    // The like withdrawn and chosen again
    setShownToasts({ like: true });
    await rateInCloud(root, 'like', 'like');
    await rateInCloud(root, undefined, 'like');
    expect(getToasts()).toEqual([]);
  });

  it('explains the first dislike at once where nothing flies', async () => {
    let confirmSave: (value: () => boolean) => void;
    const confirmation = new Promise<() => boolean>((resolve) => {
      confirmSave = resolve;
    });
    const onRate = jest.fn().mockReturnValue(confirmation);
    const global = globalState.getGlobal();
    globalState.setGlobal({ ...global, settings: { ...global.settings, animationLevel: 0 } });
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[1].click();
    TeactDOM.render(renderAnswer(1, 'dislike', onRate), root);
    await pause(20);
    expect(getToasts()).toEqual([]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
    confirmSave!(() => true);
    expect(await waitFor(() => getToasts().length > 0, 1)).toBe(true);
    expect(getIsAgentFeedbackFlying(1)).toBe(false);
    expect(getToasts()).toEqual([DISLIKED_TOAST]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toEqual({ dislike: true });
    const { tgsUrl, ...icon } = shownToasts[0].animatedIcon!;
    expect(tgsUrl).toBe(AGENT_FEEDBACK_ANIMATIONS.dislike.center);
    expect(icon).toEqual({ previewUrl: 'dislike-rest.png', size: 36 });
  });

  it('does not explain a reaction whose save failed', async () => {
    let confirmSave: (value: undefined) => void;
    const confirmation = new Promise<undefined>((resolve) => {
      confirmSave = resolve;
    });
    const onRate = jest.fn().mockReturnValue(confirmation);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    expect(await waitFor(() => !getIsAgentFeedbackFlying(1), 1)).toBe(true);
    confirmSave!(undefined);
    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    expect(getToasts()).toEqual([]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
  });

  it.each([undefined, 'dislike'] as const)('does not explain a reaction changed to %s before confirmation', async (
    feedback,
  ) => {
    let confirmSave: (value: () => boolean) => void;
    const confirmation = new Promise<() => boolean>((resolve) => {
      confirmSave = resolve;
    });
    const onRate = jest.fn().mockReturnValue(confirmation);
    let currentFeedback: AgentAnswerFeedbackV2 | undefined = 'like';
    function getIsCurrentFeedback() {
      return currentFeedback === 'like';
    }

    TeactDOM.render(renderAnswer(1, undefined, onRate), root);
    await pause(20);
    await openMenu(root);

    getCloudButtons()[0].click();
    TeactDOM.render(renderAnswer(1, 'like', onRate), root);
    expect(await waitFor(() => Boolean(getFlight()), 1)).toBe(true);
    currentFeedback = feedback;
    TeactDOM.render(renderAnswer(1, feedback, onRate), root);
    confirmSave!(getIsCurrentFeedback);
    expect(await waitFor(() => !getIsAgentFeedbackFlying(1), 1)).toBe(true);
    await pause(20);
    expect(getToasts()).toEqual([]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
  });

  it('explains a change to the other reaction once', async () => {
    setShownToasts({ like: true });
    await rateInCloud(root, 'like', 'dislike');
    expect(getToasts()).toEqual([DISLIKED_TOAST]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toEqual({ like: true, dislike: true });

    setShownToasts({ like: true, dislike: true });
    await rateInCloud(root, 'dislike', 'like');
    await rateInCloud(root, 'like', 'dislike');
    expect(getToasts()).toEqual([]);
  });

  it.each([
    ['like', false, LIKED_TOAST, SUPPORT_LIKED_TOAST],
    ['dislike', false, DISLIKED_TOAST, SUPPORT_DISLIKED_TOAST],
    ['like', true, SUPPORT_LIKED_TOAST, LIKED_TOAST],
    ['dislike', true, SUPPORT_DISLIKED_TOAST, DISLIKED_TOAST],
  ] as const)('explains %s once for each author (operator first: %s)', async (
    feedback, isOperatorFirst, firstToast, secondToast,
  ) => {
    const global = globalState.getGlobal();
    globalState.setGlobal({ ...global, settings: { ...global.settings, animationLevel: 0 } });

    await rateInCloud(root, undefined, feedback, isOperatorFirst);
    expect(getToasts()).toEqual([firstToast]);
    await rateInCloud(root, undefined, feedback, !isOperatorFirst);
    expect(getToasts()).toEqual([firstToast, secondToast]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toEqual({ [feedback]: true });
    expect(globalState.getGlobal().settings.shownAgentSupportFeedbackToasts).toEqual({ [feedback]: true });

    await rateInCloud(root, undefined, feedback, isOperatorFirst);
    await rateInCloud(root, undefined, feedback, !isOperatorFirst);
    expect(getToasts()).toEqual([firstToast, secondToast]);
  });

  it('explains nothing for a withdrawn reaction, or for a rating from the server or history', async () => {
    TeactDOM.render(renderAnswer(1, 'like'), root);
    await pause(20);

    TeactDOM.render(renderAnswer(1, 'dislike'), root);
    expect(await waitFor(() => Boolean(root.querySelector('[data-agent-feedback-badge="dislike"]')))).toBe(true);
    expect(await waitFor(() => !root.querySelector('.replacedIcon, .iconAppearing'))).toBe(true);

    await rateInCloud(root, 'dislike', 'dislike');
    expect(getToasts()).toEqual([]);
    expect(globalState.getGlobal().settings.shownAgentFeedbackToasts).toBeUndefined();
  });
});

function renderCloud(
  isOpen: boolean,
  getAnchorElement: () => HTMLElement,
  { feedback, onChange = jest.fn().mockResolvedValue(() => true) }: {
    feedback?: AgentAnswerFeedbackV2; onChange?: jest.Mock;
  } = {},
) {
  return (
    <AgentFeedbackPill
      isOpen={isOpen}
      messageId={MESSAGE_ID}
      feedback={feedback}
      getAnchorElement={getAnchorElement}
      getMessageBottom={getNoMessageBottom}
      onChange={onChange}
      onClose={jest.fn()}
    />
  );
}

// Chooses `value` in the cloud over the answer rated `feedback`, or withdraws it, rates the answer as the chat does and
// waits for the reaction to reach it. The answer's menu closed just before takes the press once it has faded out.
async function rateInCloud(
  root: HTMLElement, feedback: AgentAnswerFeedbackV2 | undefined, value: AgentAnswerFeedbackV2,
  isOperator = false,
) {
  const onRate = jest.fn().mockResolvedValue(() => true);
  TeactDOM.render(renderAnswer(1, feedback, onRate, isOperator), root);
  await pause(CLOSE_DURATION);
  await openMenu(root);
  expect(getCloudButtons()).toHaveLength(2);

  getCloudButtons()[value === 'like' ? 0 : 1].click();
  expect(onRate).toHaveBeenCalledWith(1, feedback === value ? undefined : value);
  TeactDOM.render(renderAnswer(1, feedback === value ? undefined : value, onRate, isOperator), root);
  expect(await waitFor(() => !document.querySelector('[data-agent-feedback-cloud]'))).toBe(true);
  expect(await waitFor(() => !getIsAgentFeedbackFlying(1))).toBe(true);
}

// The toasts start afresh, with the first reactions in `shown` explained already
function setShownToasts(shown: Partial<Record<AgentAnswerFeedbackV2, boolean>> | undefined) {
  const global = globalState.getGlobal();
  globalState.setGlobal({
    ...global,
    settings: { ...global.settings, shownAgentFeedbackToasts: shown, shownAgentSupportFeedbackToasts: undefined },
  });
  shownToasts.length = 0;
}

function getToasts() {
  return shownToasts.map(({ message }) => message);
}

function getNoMessageBottom() {
  return undefined;
}

function renderAnswer(
  id: number, feedback?: AgentAnswerFeedbackV2, onRate = jest.fn().mockResolvedValue(() => true), isOperator = false,
) {
  const message: AgentMessage = {
    id, text: 'You hold 12 TON', timestamp: 0, isOutgoing: false, isComplete: true, feedback,
    operator: isOperator ? { name: 'Support' } : undefined,
  };

  return <MessageBubble key={id} message={message} isDisabled={false} onRate={onRate} />;
}

function getWrapperClassName(root: HTMLElement, id: number) {
  return root.querySelector(`[data-agent-v2-message-id="${id}"] .bubble`)!.parentElement!.className;
}

function getCloudButtons() {
  return Array.from(document.querySelectorAll<HTMLButtonElement>('[data-agent-feedback-cloud] button'));
}

function getSticker(renderId: string) {
  return document.querySelector<HTMLElement>(`[data-sticker="${renderId}"]`) ?? undefined;
}

function expectSticker(renderId: string, size: number, play = 'true') {
  const sticker = getSticker(renderId);
  expect(sticker && [sticker.dataset.size, sticker.dataset.play]).toEqual([String(size), play]);
}

// An effect or a flight left playing does not reach the next test
function removeEffects() {
  document.querySelectorAll('[data-agent-feedback-effect]').forEach((effect) => effect.parentElement!.remove());
  document.querySelectorAll(FLIGHT_SELECTOR).forEach((flight) => flight.remove());
}

function dispatchPointer(target: Element, type: string) {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, button: 0 });
  Object.defineProperties(event, { pointerType: { value: 'mouse' }, pointerId: { value: 1 } });
  target.dispatchEvent(event);
}

function getBadge(root: HTMLElement) {
  return findBadge(root)!;
}

function findBadge(root: HTMLElement) {
  return root.querySelector<HTMLElement>('[data-agent-feedback-badge]') ?? undefined;
}

async function openMenu(root: HTMLElement) {
  dispatchMenuOpen(root);
  await pause(50);
}

function dispatchMenuOpen(root: HTMLElement) {
  root.querySelector('.bubble')!
    .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 200, clientY: 300 }));
}

function closeMenu() {
  document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
}

// The design's cloud over the answer, 108 × 56, with its 36 px icons 12 px and 60 px from its leading end and 10 px
// from its top
function mockLayout() {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
    if (this.matches('[data-agent-feedback-cloud]')) return toRect(282, 157, 108, 56);
    if (this.matches('[data-agent-feedback-option="like"] .icon')) return toRect(294, 167, 36, 36);
    if (this.matches('[data-agent-feedback-option="dislike"] .icon')) return toRect(342, 167, 36, 36);
    return BUBBLE_RECT;
  });
}

function toRect(left: number, top: number, width: number, height: number) {
  return {
    x: left, y: top, left, top, width, height, right: left + width, bottom: top + height, toJSON: () => undefined,
  };
}

function mockBubbleRect({ top, bottom }: { top: number; bottom: number }) {
  jest.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
    ...BUBBLE_RECT, y: top, top, bottom, height: bottom - top,
  });
}

function getEffectFrame(renderId: string) {
  return document.querySelector<HTMLElement>(`[data-agent-feedback-effect="${renderId}"]`)?.style.transform;
}

/**
 * The parts shown, sampled between tasks as the frames come, each change once, until stopped. A frame's phases run in
 * microtasks of one task, between which the page is not drawn.
 */
function recordVisibleParts(root: HTMLElement, reaction: AgentAnswerFeedbackV2) {
  const record = [getVisibleParts(root, reaction)];
  let isRecording = true;

  function sample() {
    const parts = getVisibleParts(root, reaction);
    if (record[record.length - 1] !== parts) record.push(parts);
  }

  void (async () => {
    while (isRecording) {
      await pause(1);
      if (isRecording) sample();
    }
  })();

  const recording = {
    stop() {
      isRecording = false;
      sample();
      return record;
    },
  };
  partRecordings.push(recording);

  return recording;
}

/**
 * What stands for the reaction on the screen: its icon in the cloud, the emoji flying from it, and the emoji at the
 * answer's corner
 */
function getVisibleParts(root: HTMLElement, reaction: AgentAnswerFeedbackV2) {
  const badge = root.querySelector<HTMLElement>(`[data-agent-feedback-badge="${reaction}"]`);
  const cloudIcon = document.querySelector(
    `[data-agent-feedback-cloud] [data-agent-feedback-option="${reaction}"] .icon`,
  );
  const parts = [
    badge && !getIsAwaiting(badge) && !badge.classList.contains('leaving') && 'badge',
    cloudIcon && !cloudIcon.classList.contains('iconFlown') && 'cloud',
    getFlight() && 'flight',
  ].filter(Boolean);

  return parts.join(' + ') || 'nothing';
}

// The answer's emoji waits out of sight for the reaction flying to it
function getIsAwaiting(badge: HTMLElement | undefined) {
  return Boolean(badge?.querySelector(`.icon[${AWAITING_ATTRIBUTE}]`));
}

/** The first frame of each flying emoji, as it is put on the screen */
function recordFlightStarts() {
  const starts: { frame: string[]; drawings: string[][] }[] = [];
  const observer = new MutationObserver((mutations) => {
    mutations.forEach(({ addedNodes }) => addedNodes.forEach((node) => {
      if (!(node instanceof HTMLElement) || !node.matches(FLIGHT_SELECTOR)) return;

      starts.push({
        frame: getFlightFrame(node),
        // The cloud's still, under the corner's drawing
        drawings: Array.from(node.querySelectorAll<HTMLImageElement>('.flightIconImage'))
          .map((image) => [image.getAttribute('src')!, image.style.opacity]),
      });
    }));
  });
  observer.observe(document.body, { childList: true, subtree: true });
  flightObservers.push(observer);

  return starts;
}

/** Every frame of the flying emoji until it goes, or until `isDone` */
async function recordFlight(isDone = () => !getFlight()) {
  const frames: { frame: string[]; center: { x: number; y: number }; size: number; drawings: number[] }[] = [];
  await waitFor(() => {
    const flight = getFlight();
    const frame = flight ? getFlightFrame(flight) : undefined;
    if (flight && frame && frame.join() !== frames.at(-1)?.frame.join()) {
      const [x, y] = flight.style.transform.match(/-?[\d.]+(?=px)/g)!.map(Number);
      const size = parseFloat(frame[1]);
      frames.push({
        frame,
        center: { x: x + size / 2, y: y + size / 2 },
        size,
        drawings: Array.from(flight.querySelectorAll<HTMLImageElement>('.flightIconImage'))
          .map((image) => Number(image.style.opacity)),
      });
    }

    return isDone();
  }, 1);

  return frames;
}

function getFlight() {
  return document.querySelector<HTMLElement>(FLIGHT_SELECTOR) ?? undefined;
}

function getCloudLeft(cloud: HTMLElement) {
  return cloud.style.getPropertyValue('--cloud-left');
}

function getCloudTop(cloud: HTMLElement) {
  return cloud.style.getPropertyValue('--cloud-top');
}

// The flying emoji keeps the size it is laid out at and is scaled to its current one
function getFlightFrame(flight: HTMLElement) {
  const [, translate, scale] = flight.style.transform.match(/^(translate3d\([^)]*\)) scale\(([\d.]+)\)$/)!;
  const size = Math.round(parseFloat(flight.style.width) * Number(scale) * 1000) / 1000;

  return [translate, `${size}px`];
}

async function waitFor(check: () => boolean | undefined, interval = WAIT_INTERVAL) {
  for (let attempt = 0; attempt < WAIT_DURATION / interval && !check(); attempt++) {
    await pause(interval);
  }

  return Boolean(check());
}
