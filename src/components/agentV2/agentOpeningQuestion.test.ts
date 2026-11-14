import type { MotionRect } from '../agent/helpers/agentMotion';

import { SENT_QUESTION_FLIGHT_DURATION } from '../agent/helpers/sentQuestionFlight';
import { FOLLOWUP_MORPH_DURATION } from './agentFollowupMorph';
import { startOpeningSuggestionMorph, startOpeningTextFlight } from './agentOpeningQuestion';

const mockMeasureCallbacks: NoneToVoidFunction[] = [];
jest.mock('../../lib/fasterdom/fasterdom', () => ({
  requestMeasure: (callback: NoneToVoidFunction) => mockMeasureCallbacks.push(callback),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
}));
// Class names are their own keys, so that the parts of the flight and the morph can be found by them. Style modules
// and assets resolve to one stub, which still reads as a file where an asset's URL is used.
jest.mock('./AgentV2Conversation.module.scss', () => new Proxy({}, {
  get: (target, key) => {
    if (key === '__esModule') return false;
    if (key === Symbol.toPrimitive) return () => 'test-file-stub';
    return key;
  },
}));
let mockCanAnimate = true;
jest.mock('../agent/helpers/getCanAnimate', () => ({ __esModule: true, default: () => mockCanAnimate }));

const QUESTION = 'Why does it matter?';
// The chat's slide in over the list
const SCREEN_TRANSITION_DURATION = 650;

describe('a question asked under the chat list', () => {
  let input: HTMLTextAreaElement;
  let chatScreen: HTMLDivElement;
  let bubble: HTMLDivElement;
  let text: HTMLSpanElement;
  let screenAnimations: Animation[];
  let now: number;
  const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
  const originalGetAnimations = Object.getOwnPropertyDescriptor(Element.prototype, 'getAnimations');

  beforeEach(() => {
    mockCanAnimate = true;
    mockMeasureCallbacks.length = 0;
    now = 1_000_000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    // The pseudo-elements a bubble's tail is drawn with are styled as the bubble here
    const getStyle = window.getComputedStyle.bind(window);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element: Element) => getStyle(element));
    Object.defineProperty(Element.prototype, 'animate', {
      configurable: true,
      value: () => ({ onfinish: undefined }) as unknown as Animation,
    });
    screenAnimations = [];
    Object.defineProperty(Element.prototype, 'getAnimations', {
      configurable: true,
      value(this: Element) {
        return this === chatScreen ? screenAnimations : [];
      },
    });

    // The list's field, its text padded 12 px in it
    input = document.createElement('textarea');
    input.value = QUESTION;
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
    document.body.appendChild(input);

    // The screen of the chat that opens, which shows the question in its first bubble
    chatScreen = document.createElement('div');
    const conversation = document.createElement('div');
    conversation.setAttribute('data-agent-conversation', '');
    const message = document.createElement('div');
    message.setAttribute('data-agent-v2-message-role', 'user');
    bubble = document.createElement('div');
    bubble.style.padding = '8px 12px';
    bubble.style.backgroundColor = 'rgb(0, 136, 255)';
    text = document.createElement('span');
    text.setAttribute('data-agent-question-text', '');
    text.textContent = QUESTION;
    text.style.fontSize = '15px';
    text.style.color = 'rgb(255, 255, 255)';
    const composer = document.createElement('div');
    composer.setAttribute('data-agent-composer', '');
    bubble.appendChild(text);
    message.appendChild(bubble);
    conversation.append(message, composer);
    chatScreen.appendChild(conversation);
    mockRect(bubble, {
      left: 220, top: 120, width: 160, height: 36,
    });
    mockRect(text, {
      left: 232, top: 128, width: 136, height: 20,
    });
    mockRect(composer, {
      left: 0, top: 740, width: 400, height: 60,
    });
  });

  afterEach(() => {
    input.remove();
    chatScreen.remove();
    document.body.querySelectorAll('.openingQuestionLayer').forEach((element) => element.remove());
    jest.restoreAllMocks();
    restoreProperty(Element.prototype, 'animate', originalAnimate);
    restoreProperty(Element.prototype, 'getAnimations', originalGetAnimations);
  });

  it('flies out of the field into the first bubble over the chat\'s transition, waiting at the field for it', () => {
    screenAnimations = [buildScreenAnimation(SCREEN_TRANSITION_DURATION)];
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;
    const picture = layer.querySelector<HTMLElement>('.picture')!;
    expect(picture.classList.contains('pictureFlying')).toBe(true);
    expect(picture.textContent).toBe(QUESTION);

    // The chat is not there yet: the field's text waits where it stood
    runFrame(0);
    expect(layer.querySelector('.flight')).toBeNull();
    expect(picture.parentElement).toBe(layer);

    document.body.appendChild(chatScreen);
    runFrame(16);
    const flight = layer.querySelector<HTMLElement>('.flight')!;
    const background = flight.querySelector<HTMLElement>('.flightBubble')!;
    // The text itself goes, and the bubble grows out of the list's field, as from a chat's field
    expect(picture.parentElement).toBe(flight);
    expect(background.style.transform).toBe('translate(20px, 750px)');
    expect(background.style.height).toBe('44px');
    expect(bubble.style.opacity).toBe('0');

    // Telegram's curves and its share for the bubble to come in hold over the whole transition
    runFrame(32);
    runFrame(32 + SCREEN_TRANSITION_DURATION * 0.2);
    expect(background.style.opacity).toBe('0.5');
    runFrame(32 + SENT_QUESTION_FLIGHT_DURATION * 1.5);
    expect(flight.isConnected).toBe(true);
    expect(bubble.style.opacity).toBe('0');

    // It lands as the chat arrives, and the bubble takes its place
    runFrame(32 + SCREEN_TRANSITION_DURATION);
    expect(layer.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
    expect(mockMeasureCallbacks).toHaveLength(0);
  });

  it('keeps the flight\'s time to the chat\'s transition, waiting at the field until it starts', () => {
    const screenAnimation = buildScreenAnimation(SCREEN_TRANSITION_DURATION, true);
    screenAnimations = [screenAnimation];
    document.body.appendChild(chatScreen);
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;

    runFrame(0);
    const flight = layer.querySelector<HTMLElement>('.flight')!;
    const background = flight.querySelector<HTMLElement>('.flightBubble')!;
    // A busy frame passes before the chat starts coming in, the flight standing at the field meanwhile
    runFrame(16);
    runFrame(116);
    expect(background.style.transform).toBe('translate(20px, 750px)');

    Object.assign(screenAnimation, { pending: false });
    runFrame(132);
    runFrame(16 + SCREEN_TRANSITION_DURATION);
    expect(flight.isConnected).toBe(true);

    // It lands as the chat arrives
    runFrame(132 + SCREEN_TRANSITION_DURATION);
    expect(layer.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
  });

  it('starts the flight after waiting for a chat\'s transition as long as it may', () => {
    screenAnimations = [buildScreenAnimation(SCREEN_TRANSITION_DURATION, true)];
    document.body.appendChild(chatScreen);
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;

    runFrame(0);
    runFrame(16);
    runFrame(516);
    runFrame(516 + SENT_QUESTION_FLIGHT_DURATION * 0.75);
    expect(layer.isConnected).toBe(true);
    runFrame(516 + SENT_QUESTION_FLIGHT_DURATION);
    expect(layer.isConnected).toBe(false);
  });

  it('flies over Telegram\'s own time where no screen moves', () => {
    document.body.appendChild(chatScreen);
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;

    runFrame(0);
    expect(layer.querySelector('.flight')).not.toBeNull();
    runFrame(16);
    runFrame(16 + SENT_QUESTION_FLIGHT_DURATION);
    expect(layer.isConnected).toBe(false);
    expect(bubble.style.opacity).toBe('');
  });

  it('lets the field\'s text go when the chat does not show the question in time', () => {
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;

    runFrame(0);
    expect(layer.isConnected).toBe(true);
    runFrame(1001);
    expect(layer.isConnected).toBe(false);
    expect(mockMeasureCallbacks).toHaveLength(0);
  });

  it('flies into a question the chat shows at the end of the wait, however long its layout then takes to read', () => {
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;
    runFrame(0);

    // The chat shows the question just in time, and its layout takes a slow frame to read
    document.body.appendChild(chatScreen);
    const getBubbleRect = bubble.getBoundingClientRect.bind(bubble);
    bubble.getBoundingClientRect = () => {
      now += 50;
      return getBubbleRect();
    };
    runFrame(990);

    expect(layer.querySelector('.flight')).not.toBeNull();
  });

  it('looks for the chat that opens in the document only until it finds it', () => {
    text.textContent = '';
    document.body.appendChild(chatScreen);
    const querySelectorAll = jest.spyOn(document, 'querySelectorAll');
    startOpeningTextFlight(input, QUESTION);
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;

    // The chat shows its question a few frames after it comes in
    runFrame(0);
    runFrame(16);
    text.textContent = QUESTION;
    runFrame(32);

    expect(layer.querySelector('.flight')).not.toBeNull();
    expect(querySelectorAll.mock.calls.filter(([selector]) => selector === '[data-agent-conversation]'))
      .toHaveLength(1);
  });

  it('turns a tapped suggestion into the first bubble, its pill becoming the bubble', () => {
    const button = document.createElement('button');
    button.style.borderTopLeftRadius = '80px';
    const label = document.createElement('span');
    label.className = 'followupLabel';
    label.style.fontSize = '15px';
    label.textContent = 'Explain this update';
    button.appendChild(label);
    mockRect(button, {
      left: 16, top: 600, width: 180, height: 40,
    });
    mockRect(label, {
      left: 47, top: 610, width: 137, height: 20,
    });
    document.body.appendChild(button);
    text.textContent = 'Explain this update';
    document.body.appendChild(chatScreen);

    startOpeningSuggestionMorph(button, 'Explain this update');
    const layer = document.body.querySelector<HTMLElement>('.openingQuestionLayer')!;
    runFrame(0);
    expect(layer.querySelector('.followupMorphPill')).not.toBeNull();
    expect(button.style.visibility).toBe('hidden');
    expect(bubble.style.opacity).toBe('0');

    runFrame(16);
    runFrame(16 + FOLLOWUP_MORPH_DURATION);
    expect(layer.isConnected).toBe(false);
    expect(button.style.visibility).toBe('');
    expect(bubble.style.opacity).toBe('');
    button.remove();
  });

  it('leaves the question to the chat where motion is off', () => {
    mockCanAnimate = false;
    document.body.appendChild(chatScreen);

    startOpeningTextFlight(input, QUESTION);
    expect(document.body.querySelector('.openingQuestionLayer')).toBeNull();
    expect(mockMeasureCallbacks).toHaveLength(0);
  });

  function runFrame(time: number) {
    now = 1_000_000 + time;
    const callbacks = mockMeasureCallbacks.splice(0);
    callbacks.forEach((callback) => callback());
  }
});

// The animation of a screen coming in, at its start, or before it while `isPending`
function buildScreenAnimation(duration: number, isPending = false) {
  return {
    currentTime: isPending ? undefined : 0,
    pending: isPending,
    effect: { getComputedTiming: () => ({ endTime: duration }) },
  } as unknown as Animation;
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

function restoreProperty(target: object, key: PropertyKey, descriptor?: PropertyDescriptor) {
  if (descriptor) {
    Object.defineProperty(target, key, descriptor);
  } else {
    Reflect.deleteProperty(target, key);
  }
}
