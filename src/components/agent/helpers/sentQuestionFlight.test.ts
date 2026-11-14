import type { MotionRect } from './agentMotion';
import type { SentFlightStart, SentFlightTarget } from './sentQuestionFlight';

import {
  createSentTextPicture,
  getSentFlightState,
  measureSentQuestionFlight,
  SENT_QUESTION_FLIGHT_DURATION,
} from './sentQuestionFlight';

const mockMeasureCallbacks: NoneToVoidFunction[] = [];
jest.mock('../../../lib/fasterdom/fasterdom', () => ({
  requestMeasure: (callback: NoneToVoidFunction) => mockMeasureCallbacks.push(callback),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
}));
// Class names are their own keys, so that the flight's parts can be found by them
jest.mock('../SentQuestionFlight.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

// The field at the bottom of the layer, whose text box is padded 12 px in it, and the question's bubble over it, all in
// the layer, which starts 100 px down the window
const START: SentFlightStart = {
  field: {
    left: 20, top: 650, width: 300, height: 44,
  },
  textOrigin: { x: 32, y: 662 },
  fontSize: 16,
};
const TARGET: SentFlightTarget = {
  frame: {
    left: 220, top: 300, width: 160, height: 36,
  },
  textOffset: { x: 12, y: 8 },
  fontSize: 15,
};

describe('getSentFlightState', () => {
  it('grows the bubble out of the field around the text, which moves into it, as Telegram\'s send does', () => {
    const start = getSentFlightState(START, TARGET, 0, false);
    // The bubble starts as tall as the field, its start as far from the field's text as from its own, and its end a
    // little past its own
    expect(start.frame).toEqual({
      left: 20, top: 650, width: 384 - 20, height: 44,
    });
    expect(start.textOrigin).toEqual({ x: 32, y: 662 });
    expect(start.fieldTextScale).toBe(1);
    expect(start.bubbleTextScale).toBeCloseTo(16 / 15, 6);
    expect(start.appearance).toBe(0);
    expect(start.clipShare).toBe(0);

    // The bubble and its text come in, and the field's text goes, over the first 40% of the time
    expect(getSentFlightState(START, TARGET, 0.2, false).appearance).toBeCloseTo(0.5, 6);
    expect(getSentFlightState(START, TARGET, 0.4, false).appearance).toBe(1);

    // The text goes across and takes its size well ahead of going up, on Telegram's two curves
    const early = getSentFlightState(START, TARGET, 0.2, false);
    const acrossShare = (early.textOrigin.x - 32) / (232 - 32);
    const upShare = (662 - early.textOrigin.y) / (662 - 308);
    expect(acrossShare).toBeGreaterThan(0.8);
    expect(upShare).toBeLessThan(0.4);
    expect(early.clipShare).toBeCloseTo(acrossShare, 6);

    const end = getSentFlightState(START, TARGET, 1, false);
    expect(end.frame).toEqual(TARGET.frame);
    expect(end.textOrigin).toEqual({ x: 232, y: 308 });
    expect(end.fieldTextScale).toBeCloseTo(15 / 16, 6);
    expect(end.bubbleTextScale).toBeCloseTo(1, 6);
    expect(end.appearance).toBe(1);
    expect(end.clipShare).toBe(1);
  });

  it('never goes down out of the field, aiming at the field\'s line for a bubble still under it', () => {
    const target: SentFlightTarget = { ...TARGET, frame: { ...TARGET.frame, top: 800 } };

    for (const fraction of [0.25, 0.5, 0.75]) {
      const state = getSentFlightState(START, target, fraction, false);
      expect(state.frame.top).toBeLessThanOrEqual(650);
      expect(state.textOrigin.y).toBeLessThanOrEqual(662);
    }
    const end = getSentFlightState(START, target, 1, false);
    expect(end.frame).toEqual({ ...target.frame, top: 650 });
    expect(end.textOrigin.y).toBe(658);
  });

  it('mirrors the bubble\'s growth in a right-to-left layout', () => {
    // The field's text starts at its right, and the question's bubble stands on the left
    const start: SentFlightStart = { ...START, textOrigin: { x: 308, y: 662 } };
    const target: SentFlightTarget = { ...TARGET, frame: { ...TARGET.frame, left: 20 } };

    expect(getSentFlightState(start, target, 0, true).frame).toEqual({
      left: 16, top: 650, width: 320 - 16, height: 44,
    });
    expect(getSentFlightState(start, target, 0, true).textOrigin.x).toBe(308);
    expect(getSentFlightState(start, target, 1, true).frame).toEqual(target.frame);
    expect(getSentFlightState(start, target, 1, true).textOrigin.x).toBe(168);
  });
});

describe('measureSentQuestionFlight', () => {
  let layer: HTMLDivElement;
  let input: HTMLTextAreaElement;
  let bubble: HTMLDivElement;
  let text: HTMLSpanElement;
  let bubbleRect: MotionRect;
  let fieldRow: HTMLDivElement;
  let now: number;

  beforeEach(() => {
    mockMeasureCallbacks.length = 0;
    now = 1_000_000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    // The pseudo-element a bubble's tail is drawn with is styled as the bubble here
    const getStyle = window.getComputedStyle.bind(window);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element: Element) => getStyle(element));

    layer = document.createElement('div');
    mockRect(layer, {
      left: 0, top: 100, width: 400, height: 800,
    });
    input = document.createElement('textarea');
    input.value = 'Why does it matter?';
    input.style.padding = '12px';
    input.style.fontSize = '16px';
    input.style.color = 'rgb(0, 0, 0)';
    Object.defineProperties(input, {
      clientWidth: { configurable: true, value: 300 },
      clientHeight: { configurable: true, value: 44 },
    });
    mockRect(input, {
      left: 20, top: 750, width: 300, height: 44,
    });
    bubble = document.createElement('div');
    bubble.style.padding = '8px 12px';
    bubble.style.backgroundColor = 'rgb(0, 136, 255)';
    bubble.style.borderTopLeftRadius = '18px';
    text = document.createElement('span');
    text.textContent = 'Why does it matter?';
    text.style.fontSize = '15px';
    text.style.color = 'rgb(255, 255, 255)';
    bubble.appendChild(text);
    bubbleRect = {
      left: 220, top: 400, width: 160, height: 36,
    };
    bubble.getBoundingClientRect = () => toDomRect(bubbleRect);
    mockRect(text, {
      left: 232, top: 408, width: 136, height: 20,
    });
    // The field's row, whose top the flight passes under
    fieldRow = document.createElement('div');
    mockRect(fieldRow, {
      left: 0, top: 740, width: 400, height: 60,
    });
    document.body.append(layer, input, bubble);
  });

  afterEach(() => {
    layer.remove();
    input.remove();
    bubble.remove();
    jest.restoreAllMocks();
  });

  it('pictures the field\'s text in its place, out of sight until the flight', () => {
    const picture = createSentTextPicture(input, layer)!;

    expect(picture.element.parentElement).toBe(layer);
    expect(picture.text.textContent).toBe('Why does it matter?');
    expect(picture.box).toEqual({
      left: 32, top: 662, width: 276, height: 20,
    });
    expect(picture.field).toEqual({
      left: 20, top: 650, width: 300, height: 44,
    });
    expect(picture.element.style.left).toBe('32px');
    expect(picture.element.style.top).toBe('662px');
    expect(picture.fontSize).toBe(16);
    expect(picture.color).toBe('rgb(0, 0, 0)');
    expect(picture.element.classList.contains('pictureFlying')).toBe(false);

    // A picture that holds the text for a chat on another screen shows at once
    expect(createSentTextPicture(input, layer, true)!.element.classList.contains('pictureFlying')).toBe(true);
  });

  it('flies the field\'s text into the bubble wherever the list takes it, and hands over to the bubble', () => {
    const picture = createSentTextPicture(input, layer)!;
    const finish = measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => fieldRow)!();

    const flight = layer.querySelector<HTMLElement>('.flight')!;
    const background = flight.querySelector<HTMLElement>('.flightBubble')!;
    const bubbleText = flight.querySelector<HTMLElement>('.flightText')!;
    expect(bubble.style.opacity).toBe('0');
    expect(picture.element.parentElement).toBe(flight);
    expect(picture.element.classList.contains('pictureFlying')).toBe(true);
    expect(background.querySelector('.flightTail')).not.toBeNull();
    expect(bubbleText.textContent).toBe('Why does it matter?');
    // It starts from the field, the bubble not shown yet, unclipped
    expect(background.style.transform).toBe('translate(20px, 650px)');
    expect(background.style.width).toBe('364px');
    expect(background.style.height).toBe('44px');
    expect(background.style.opacity).toBe('0');
    expect(picture.element.style.opacity).toBe('1');
    expect(flight.style.height).toBe('800px');

    runFrame(0);
    // The field's text takes the bubble's colour as it gives way to the bubble's text
    runFrame(SENT_QUESTION_FLIGHT_DURATION * 0.2);
    expect(picture.lines.style.color).toBe('rgb(128, 128, 128)');
    expect(background.style.opacity).toBe('0.5');
    expect(bubbleText.style.opacity).toBe('0.5');

    // The list takes the question up meanwhile, and the flight goes after it
    bubbleRect = { ...bubbleRect, top: 200 };
    runFrame(SENT_QUESTION_FLIGHT_DURATION / 2);
    const { top } = parseTranslate(background.style.transform);
    expect(top).toBeLessThan(650);
    expect(top).toBeGreaterThan(100);
    // It passes under the field's row once it is past it
    expect(parseFloat(flight.style.height)).toBeLessThan(800);
    expect(parseFloat(flight.style.height)).toBeGreaterThanOrEqual(640);
    expect(bubble.style.opacity).toBe('0');

    runFrame(SENT_QUESTION_FLIGHT_DURATION);
    expect(flight.isConnected).toBe(false);
    expect(picture.element.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
    expect(mockMeasureCallbacks).toHaveLength(0);
    finish();
  });

  it('ends the flight where it stands, the bubble showing at once', () => {
    const picture = createSentTextPicture(input, layer)!;
    const finish = measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => undefined)!();
    runFrame(0);

    finish();
    expect(layer.querySelector('.flight')).toBeNull();
    expect(bubble.style.opacity).toBe('');
    runFrame(SENT_QUESTION_FLIGHT_DURATION / 2);
    expect(layer.querySelector('.flight')).toBeNull();
  });

  it('stretches over a longer time on the same curves, and tells when it ends', () => {
    const onEnd = jest.fn();
    const picture = createSentTextPicture(input, layer)!;
    measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => undefined, 600, onEnd)!();
    const background = layer.querySelector<HTMLElement>('.flightBubble')!;

    runFrame(0);
    // The bubble comes in over the first 40% of the longer time
    runFrame(120);
    expect(background.style.opacity).toBe('0.5');
    runFrame(SENT_QUESTION_FLIGHT_DURATION);
    expect(background.isConnected).toBe(true);
    expect(onEnd).not.toHaveBeenCalled();

    runFrame(600);
    expect(background.isConnected).toBe(false);
    expect(onEnd).toHaveBeenCalledTimes(1);
  });

  it('keeps the text in the field while the list brings the bubble up from under it, then flies it up', () => {
    bubbleRect = { ...bubbleRect, top: 1000 };
    const picture = createSentTextPicture(input, layer)!;
    measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => fieldRow)!();
    const background = layer.querySelector<HTMLElement>('.flightBubble')!;

    // The list brings the question up from under the field, 20 px a frame
    for (let time = 0; time <= 200; time += 20) {
      bubbleRect = { ...bubbleRect, top: 1000 - time };
      runFrame(time);
    }
    expect(background.style.transform).toBe('translate(20px, 650px)');
    expect(background.style.opacity).toBe('0');
    expect(picture.element.style.opacity).toBe('1');
    expect(bubble.style.opacity).toBe('0');

    // Its time starts once the bubble is over the field
    bubbleRect = { ...bubbleRect, top: 740 };
    runFrame(220);
    runFrame(220 + SENT_QUESTION_FLIGHT_DURATION * 0.2);
    expect(background.style.opacity).toBe('0.5');
    expect(parseTranslate(background.style.transform).top).toBeLessThanOrEqual(650);
    runFrame(220 + SENT_QUESTION_FLIGHT_DURATION);
    expect(background.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
  });

  it('flies along the field\'s line toward a bubble that the list leaves under the field', () => {
    bubbleRect = { ...bubbleRect, top: 1000 };
    const picture = createSentTextPicture(input, layer)!;
    measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => fieldRow)!();
    const background = layer.querySelector<HTMLElement>('.flightBubble')!;

    runFrame(0);
    runFrame(40);
    expect(background.style.opacity).toBe('0');

    // A bubble that has stopped rising is not waited for
    runFrame(60);
    runFrame(60 + SENT_QUESTION_FLIGHT_DURATION / 2);
    expect(background.style.opacity).toBe('1');
    expect(parseTranslate(background.style.transform).top).toBe(650);
    runFrame(60 + SENT_QUESTION_FLIGHT_DURATION);
    expect(background.isConnected).toBe(false);
  });

  it('does not fly a question of more than ten lines, as Telegram does not', () => {
    const picture = createSentTextPicture(input, layer)!;
    bubble.style.lineHeight = '20px';
    bubbleRect = { ...bubbleRect, height: 8 + 11 * 20 + 8 };

    expect(measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => undefined)).toBeUndefined();

    bubbleRect = { ...bubbleRect, height: 8 + 10 * 20 + 8 };
    expect(measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => undefined)).toBeDefined();
  });

  it('does not fly a question whose picture is too old to be its own', () => {
    const picture = createSentTextPicture(input, layer)!;
    now += 1500;

    expect(measureSentQuestionFlight(picture, bubble, text, () => bubble, layer, () => undefined)).toBeUndefined();
  });

  function runFrame(time: number) {
    now = 1_000_000 + time;
    const callbacks = mockMeasureCallbacks.splice(0);
    callbacks.forEach((callback) => callback());
  }
});

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
  } as DOMRect;
}
