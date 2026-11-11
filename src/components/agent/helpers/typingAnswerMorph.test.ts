import type { MotionRect } from './agentMotion';

import {
  getStatusLanding,
  getTypingAnswerClip,
  startTypingAnswerMorph,
  TYPING_ANSWER_MORPH_DURATION,
} from './typingAnswerMorph';

const mockMeasureCallbacks: NoneToVoidFunction[] = [];
jest.mock('../../../lib/fasterdom/fasterdom', () => ({
  requestForcedReflow: (callback: () => NoneToVoidFunction | undefined) => callback()?.(),
  requestMeasure: (callback: NoneToVoidFunction) => mockMeasureCallbacks.push(callback),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
}));
// Class names are their own keys, so that the row's top and status can be found by them
jest.mock('../AgentRunActivity.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

interface RecordedAnimation {
  element: Element;
  keyframes: Keyframe[];
  options: KeyframeAnimationOptions;
}

const ROW: MotionRect = {
  left: 8, top: 100, width: 220, height: 34,
};
const BUBBLE: MotionRect = {
  left: 8, top: 100, width: 300, height: 64,
};

describe('getTypingAnswerClip', () => {
  it('shows the bubble within the row\'s frame at first and whole, its tail included, by the end', () => {
    const start = {
      left: 0, top: 0, width: ROW.width, height: ROW.height,
    };

    expect(getTypingAnswerClip(start, BUBBLE, 20, 0)).toEqual({ rect: start, radius: 17 });
    expect(getTypingAnswerClip(start, BUBBLE, 20, 1)).toEqual({
      rect: {
        left: -8, top: -8, width: 316, height: 80,
      },
      radius: 28,
    });
    // The growth keeps up with an answer that streams in meanwhile
    expect(getTypingAnswerClip(start, { ...BUBBLE, height: 200 }, 20, 1).rect.height).toBe(216);
  });
});

describe('getStatusLanding', () => {
  it('moves the status onto the answer\'s first characters, from its leading edge', () => {
    const status = {
      left: 46, top: 107, width: 170, height: 20,
    };

    expect(getStatusLanding(status, { x: 20, y: 108 }, false)).toEqual({ x: -26, y: 1 });
    expect(getStatusLanding(status, { x: 296, y: 108 }, true)).toEqual({ x: 80, y: 1 });
  });
});

describe('startTypingAnswerMorph', () => {
  let row: HTMLDivElement;
  let top: HTMLSpanElement;
  let status: HTMLSpanElement;
  let bubble: HTMLDivElement;
  let content: HTMLDivElement;
  let animations: RecordedAnimation[];
  let now: number;
  const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');

  beforeEach(() => {
    animations = [];
    mockMeasureCallbacks.length = 0;
    now = 1_000_000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value(this: Element, keyframes: Keyframe[], options: KeyframeAnimationOptions) {
        animations.push({ element: this, keyframes, options });
        return {} as Animation;
      },
    });

    row = document.createElement('div');
    top = document.createElement('span');
    top.className = 'icon';
    status = document.createElement('span');
    status.className = 'steps';
    row.append(top, status);
    bubble = document.createElement('div');
    bubble.style.padding = '8px 12px';
    bubble.style.borderTopLeftRadius = '20px';
    content = document.createElement('div');
    bubble.appendChild(content);
    Object.defineProperties(bubble, {
      offsetWidth: { configurable: true, get: () => BUBBLE.width },
      offsetHeight: { configurable: true, get: () => BUBBLE.height },
    });
    mockRect(row, ROW);
    mockRect(top, {
      left: 18, top: 105, width: 24, height: 24,
    });
    mockRect(status, {
      left: 46, top: 107, width: 170, height: 20,
    });
    mockRect(bubble, BUBBLE);
    document.body.append(row, bubble);
  });

  afterEach(() => {
    row.remove();
    bubble.remove();
    jest.restoreAllMocks();
    if (originalAnimate) {
      Object.defineProperty(Element.prototype, 'animate', originalAnimate);
    } else {
      Reflect.deleteProperty(Element.prototype, 'animate');
    }
  });

  it('turns the typing row into the answer that takes its place', () => {
    startTypingAnswerMorph(row, bubble);

    // The row stays over the bubble as its top and its status leave
    expect(row.classList.contains('answerPlaceholderMorphing')).toBe(true);
    const [topAway, statusMove, statusDissolve, contentFocus, bubbleFade] = animations;
    expect(topAway.element).toBe(top);
    expect(topAway.keyframes[1]).toEqual({ translate: '-14px -10px', scale: '0.2', opacity: 0 });
    expect(topAway.options).toMatchObject({ duration: 300, easing: 'cubic-bezier(0.38, 0.7, 0.125, 1)' });
    // The status moves onto the answer's first characters as it blurs away, and the answer's text comes into focus
    expect(statusMove.element).toBe(status);
    expect(statusMove.keyframes[1]).toEqual({ translate: '-26px 1px' });
    expect(statusMove.options.duration).toBe(TYPING_ANSWER_MORPH_DURATION);
    expect(statusDissolve.keyframes[1]).toEqual({ opacity: 0, filter: 'blur(0.5rem)' });
    expect(statusDissolve.options).toMatchObject({ duration: 300, easing: 'ease-in' });
    expect(contentFocus.element).toBe(content);
    expect(contentFocus.keyframes[0]).toEqual({ opacity: 0, filter: 'blur(0.5rem)' });
    expect(contentFocus.options).toMatchObject({ duration: 300, delay: 60, easing: 'ease-out' });
    expect(bubbleFade.element).toBe(bubble);
    expect(bubbleFade.options.duration).toBe(200);

    // The bubble shows within the row's frame at first, and whole once the morph ends
    expect(bubble.style.getPropertyValue('clip-path')).toBe('inset(0px 80px 30px 0px round 17px)');
    runFrame(TYPING_ANSWER_MORPH_DURATION / 2);
    expect(bubble.style.getPropertyValue('clip-path')).not.toBe('inset(0px 80px 30px 0px round 17px)');
    runFrame(TYPING_ANSWER_MORPH_DURATION);
    expect(bubble.style.getPropertyValue('clip-path')).toBe('');
    expect(mockMeasureCallbacks).toHaveLength(0);
  });

  it('moves the top away toward the leading edge of a right-to-left chat', () => {
    bubble.style.direction = 'rtl';

    startTypingAnswerMorph(row, bubble);

    expect(animations[0].keyframes[1]).toMatchObject({ translate: '14px -10px' });
    // The status's trailing edge lands where the answer's text starts, inside the bubble's end padding
    expect(animations[1].keyframes[1]).toEqual({ translate: `${308 - 12 - 216}px 1px` });
  });

  function runFrame(time: number) {
    now = 1_000_000 + time;
    const callbacks = mockMeasureCallbacks.splice(0);
    callbacks.forEach((callback) => callback());
  }
});

function mockRect(element: HTMLElement, {
  left, top, width, height,
}: MotionRect) {
  element.getBoundingClientRect = () => ({
    left, top, width, height, right: left + width, bottom: top + height, x: left, y: top, toJSON: () => undefined,
  });
}
