import type { MotionRect } from '../agent/helpers/agentMotion';
import type { FollowupMorphStart, FollowupMorphTarget } from './agentFollowupMorph';

import { getTelegramProgress } from '../agent/helpers/agentMotion';
import {
  captureFollowupSource,
  FOLLOWUP_MORPH_BLUR,
  FOLLOWUP_MORPH_DURATION,
  getFollowupMorphState,
  getRippleOrder,
  measureFollowupMorph,
  rippleFollowupsAway,
} from './agentFollowupMorph';

const mockMeasureCallbacks: NoneToVoidFunction[] = [];
jest.mock('../../lib/fasterdom/fasterdom', () => ({
  requestMeasure: (callback: NoneToVoidFunction) => mockMeasureCallbacks.push(callback),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
}));
// Class names are their own keys, so that the morph's parts can be found by them
jest.mock('./AgentV2Conversation.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

interface RecordedAnimation {
  element: Element;
  keyframes: Keyframe[];
  options: KeyframeAnimationOptions;
  animation: Animation;
}

// A short suggestion, and one whose lines break differently in its narrow pill and in the bubble
const MORPHS: { name: string; start: FollowupMorphStart; target: FollowupMorphTarget }[] = [{
  name: 'Why does it matter?',
  start: {
    frame: {
      left: 16, top: 480, width: 180, height: 40,
    },
    titleOffset: { x: 35, y: 10 },
    titleFontSize: 15,
    radius: 20,
  },
  target: {
    frame: {
      left: 210, top: 560, width: 176, height: 40,
    },
    textOffset: { x: 12, y: 9 },
    fontSize: 17,
    radii: [20, 20, 0, 20],
  },
}, {
  name: 'What would happen to my staking rewards if the network upgrade is delayed again?',
  start: {
    frame: {
      left: 16, top: 440, width: 200, height: 80,
    },
    titleOffset: { x: 35, y: 10 },
    titleFontSize: 15,
    radius: 20,
  },
  target: {
    frame: {
      left: 70, top: 560, width: 316, height: 82,
    },
    textOffset: { x: 12, y: 9 },
    fontSize: 17,
    radii: [20, 20, 0, 20],
  },
}];

describe('getFollowupMorphState', () => {
  it('turns a tapped suggestion into its question\'s bubble frame by frame', () => {
    const frameCount = 54;

    MORPHS.forEach(({ start, target }) => {
      const distance = Math.max(
        Math.abs(target.frame.left - start.frame.left),
        Math.abs(getRight(target.frame) - getRight(start.frame)),
        Math.abs(target.frame.top - start.frame.top),
        Math.abs(getBottom(target.frame) - getBottom(start.frame)),
      );
      let previous: ReturnType<typeof getFollowupMorphState> | undefined;
      let previousTailScale = 0;

      for (let index = 0; index <= frameCount; index++) {
        const progress = getTelegramProgress(index / frameCount);
        const state = getFollowupMorphState(start, target, progress);

        if (index === 0) {
          // The pill starts where it was, without a tail
          expect(state.frame).toEqual(start.frame);
          expect(state.tailScale).toBeUndefined();
          expect(state.pillOpacity).toBe(1);
        }
        if (previous) {
          // Each frame moves the edges as far as the morph's curve goes over that frame, and no further
          const largestStep = distance * (progress - getTelegramProgress((index - 1) / frameCount)) + 0.5;
          [
            [state.frame.left, previous.frame.left],
            [getRight(state.frame), getRight(previous.frame)],
            [state.frame.top, previous.frame.top],
            [getBottom(state.frame), getBottom(previous.frame)],
          ].forEach(([edge, last]) => {
            expect(Math.abs(edge - last)).toBeLessThanOrEqual(largestStep);
          });
        }
        // One text at a time, the two standing on one point
        expect(state.titleOpacity + state.textOpacity).toBeCloseTo(1, 3);
        if (state.titleOpacity > 0.01 && state.textOpacity > 0.01) {
          // Never both line layouts sharp at once
          expect(Math.max(state.titleBlur, state.textBlur)).toBeGreaterThanOrEqual(FOLLOWUP_MORPH_BLUR / 2 - 0.001);
        }
        if (state.textOpacity > 0.99) expect(state.textBlur).toBeCloseTo(0, 3);
        if (state.tailScale !== undefined) {
          // The tail grows out of its corner once the fill is the bubble's, and only grows
          expect(state.tailScale).toBeGreaterThanOrEqual(previousTailScale);
          expect(state.fillOpacity).toBe(1);
          expect(state.textOpacity).toBe(1);
          previousTailScale = state.tailScale;
        }
        state.radii.forEach((radius) => {
          expect(radius).toBeLessThanOrEqual(state.frame.height / 2);
        });
        previous = state;
      }

      // The last frame is the bubble with its tail, its text in focus at its own size
      const end = previous!;
      expect(end.frame).toEqual(target.frame);
      expect(end.radii).toEqual(target.radii);
      expect(end.textOffset).toEqual(target.textOffset);
      expect(end.textScale).toBeCloseTo(1, 6);
      expect(end.titleScale).toBeCloseTo(17 / 15, 6);
      expect(end.textOpacity).toBe(1);
      expect(end.textBlur).toBe(0);
      expect(end.titleOpacity).toBe(0);
      expect(end.pillOpacity).toBe(0);
      expect(end.tailScale).toBeCloseTo(1, 6);
    });
  });
});

describe('getRippleOrder', () => {
  it('lets the suggestions nearest to the tapped one leave first', () => {
    const rects = [460, 410, 360].map((top) => ({
      left: 16, top, width: 180, height: 40,
    }));

    expect(getRippleOrder(rects, {
      left: 16, top: 310, width: 180, height: 40,
    })).toEqual([2, 1, 0]);
  });
});

describe('follow-up motion in the chat', () => {
  let layer: HTMLDivElement;
  let row: HTMLDivElement;
  let buttons: HTMLButtonElement[];
  let animations: RecordedAnimation[];
  let now: number;
  const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');

  beforeEach(() => {
    animations = [];
    mockMeasureCallbacks.length = 0;
    now = 1_000_000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    // The pseudo-elements a bubble's tail is drawn with are styled as the bubble here
    const getStyle = window.getComputedStyle.bind(window);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element: Element) => getStyle(element));
    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value(this: Element, keyframes: Keyframe[], options: KeyframeAnimationOptions) {
        const animation = { onfinish: undefined } as unknown as Animation;
        animations.push({
          element: this, keyframes, options, animation,
        });
        return animation;
      },
    });

    layer = document.createElement('div');
    mockRect(layer, {
      left: 0, top: 0, width: 400, height: 800,
    });
    row = document.createElement('div');
    buttons = [0, 1, 2].map((index) => {
      const button = document.createElement('button');
      button.className = 'followupButton';
      button.dataset.agentFollowupId = `followup-${index}`;
      button.style.borderTopLeftRadius = '80px';
      const label = document.createElement('span');
      label.className = 'followupLabel';
      label.style.fontSize = '15px';
      label.textContent = `Explain this update ${index}`;
      button.appendChild(label);
      mockRect(button, {
        left: 16, top: 400 + index * 52, width: 180, height: 40,
      });
      mockRect(label, {
        left: 47, top: 410 + index * 52, width: 137, height: 20,
      });
      row.appendChild(button);
      return button;
    });
    document.body.append(layer, row);
  });

  afterEach(() => {
    layer.remove();
    row.remove();
    jest.restoreAllMocks();
    if (originalAnimate) {
      Object.defineProperty(Element.prototype, 'animate', originalAnimate);
    } else {
      Reflect.deleteProperty(Element.prototype, 'animate');
    }
  });

  it('ripples the suggestions beside the tapped one away, the nearest first, and shows any left again', () => {
    rippleFollowupsAway(buttons[0], layer);

    const pictures = Array.from(layer.children) as HTMLElement[];
    expect(pictures.map((picture) => picture.textContent)).toEqual(['Explain this update 1', 'Explain this update 2']);
    pictures.forEach((picture) => {
      expect(picture.hasAttribute('data-agent-followup-id')).toBe(false);
      expect(picture.tabIndex).toBe(-1);
    });
    // The tapped one stays for its morph, while the others leave as pictures
    expect(buttons.map((button) => button.style.visibility)).toEqual(['', 'hidden', 'hidden']);
    expect(animations.map(({ element }) => element)).toEqual(pictures);
    expect(animations.map(({ options }) => options.delay)).toEqual([0, 30]);
    expect(animations[0].keyframes[1]).toEqual({ opacity: 0, transform: 'scale(0.95)', filter: 'blur(4px)' });
    expect(animations[0].options).toMatchObject({ duration: 200, easing: 'ease-out' });

    animations.forEach(({ animation }) => animation.onfinish!({} as AnimationPlaybackEvent));
    expect(layer.children).toHaveLength(0);
    expect(buttons.map((button) => button.style.visibility)).toEqual(['', '', '']);
  });

  it('turns the tapped suggestion into the bubble, which shows at once as the morph ends', () => {
    const source = captureFollowupSource(buttons[1])!;
    expect(source.start).toEqual({
      frame: {
        left: 16, top: 452, width: 180, height: 40,
      },
      titleOffset: { x: 31, y: 10 },
      titleFontSize: 15,
      // The pill's glass is rounded as far as its height allows
      radius: 20,
    });
    // The pill's glass, without its title and arrow
    expect(source.pill.childElementCount).toBe(0);
    expect(source.title.textContent).toBe('Explain this update 1');

    const bubble = document.createElement('div');
    const text = document.createElement('span');
    text.textContent = 'Explain this update 1';
    bubble.appendChild(text);
    document.body.appendChild(bubble);
    let bubbleRect: MotionRect = {
      left: 210, top: 700, width: 176, height: 38,
    };
    bubble.getBoundingClientRect = () => toDomRect(bubbleRect);
    mockRect(text, {
      left: 222, top: 709, width: 152, height: 20,
    });

    const finish = measureFollowupMorph(source, bubble, text, () => bubble, layer)!();
    const morph = layer.querySelector<HTMLElement>('.followupMorph')!;
    expect(morph.style.transform).toBe('translate(16px, 452px)');
    expect(bubble.style.opacity).toBe('0');
    expect(buttons[1].style.visibility).toBe('hidden');

    // The morph follows the bubble as the list takes it up
    runFrame(0);
    bubbleRect = { ...bubbleRect, top: 500 };
    runFrame(FOLLOWUP_MORPH_DURATION / 2);
    const { top } = parseTranslate(morph.style.transform);
    expect(top).toBeLessThan(500);
    expect(top).toBeGreaterThan(452);
    expect(morph.isConnected).toBe(true);
    expect(bubble.style.opacity).toBe('0');

    runFrame(FOLLOWUP_MORPH_DURATION);
    expect(morph.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
    expect(mockMeasureCallbacks).toHaveLength(0);
    finish();
    bubble.remove();
  });

  function runFrame(time: number) {
    now = 1_000_000 + time;
    const callbacks = mockMeasureCallbacks.splice(0);
    callbacks.forEach((callback) => callback());
  }
});

function getRight({ left, width }: MotionRect) {
  return left + width;
}

function getBottom({ top, height }: MotionRect) {
  return top + height;
}

function parseTranslate(transform: string) {
  const [, left, top] = transform.match(/translate\(([-\d.]+)px, ([-\d.]+)px\)/u)!;
  return { left: Number(left), top: Number(top) };
}

function mockRect(element: HTMLElement, rect: MotionRect) {
  element.getBoundingClientRect = () => toDomRect(rect);
}

function toDomRect({
  left, top, width, height,
}: MotionRect) {
  return {
    left, top, width, height, right: left + width, bottom: top + height, x: left, y: top, toJSON: () => undefined,
  };
}
