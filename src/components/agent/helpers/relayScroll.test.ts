import { QUESTION_SPRING_DURATION } from './agentMotion';
import { finishRelayScroll, measureRelayScroll } from './relayScroll';

const mockMutations: NoneToVoidFunction[] = [];
jest.mock('../../../lib/fasterdom/fasterdom', () => ({
  requestForcedReflow: (callback: () => NoneToVoidFunction | undefined) => callback()?.(),
  requestMeasure: (callback: NoneToVoidFunction) => callback(),
  requestMutation: (callback: NoneToVoidFunction) => mockMutations.push(callback),
}));

describe('measureRelayScroll', () => {
  let parent: HTMLDivElement;
  let now: jest.SpyInstance;

  beforeEach(() => {
    parent = document.createElement('div');
    document.body.appendChild(parent);
    now = jest.spyOn(Date, 'now').mockReturnValue(1000);
  });

  afterEach(() => {
    parent.remove();
    mockMutations.length = 0;
    now.mockRestore();
  });

  function createList(scrollTop: number) {
    const list = document.createElement('div');
    list.innerHTML = '<div data-agent-v2-message-id="1">Answer</div>';
    parent.appendChild(list);
    Object.defineProperties(list, {
      scrollTop: { value: scrollTop, writable: true },
      scrollHeight: { value: 3000 },
      clientHeight: { value: 500 },
      offsetTop: { value: 40 },
      offsetLeft: { value: 0 },
      offsetWidth: { value: 300 },
      offsetHeight: { value: 500 },
      offsetParent: { value: parent },
    });

    return list;
  }

  function flushFrame() {
    mockMutations.splice(0).forEach((callback) => callback());
  }

  it('leaves a target within a screen to the caller', () => {
    const list = createList(2000);

    expect(measureRelayScroll(list, () => 2500)).toBeUndefined();
  });

  it('stands at a target more than a screen away at once, the rows that were on screen sliding out', () => {
    const list = createList(0);
    const onEnd = jest.fn();

    measureRelayScroll(list, () => 2500, onEnd)!();
    const departing = list.nextElementSibling as HTMLElement;
    expect(list.scrollTop).toBe(2500);
    expect(departing.hasAttribute('data-agent-departing-rows')).toBe(true);
    expect(departing.textContent).toBe('Answer');
    expect(departing.style.top).toBe('40px');
    expect(departing.style.transform).toBe('translateY(0px)');
    expect(list.style.transform).toBe('translateY(500px)');

    // The rows go up by a screen as the target's rows come up after them, on the question's spring
    now.mockReturnValue(1000 + QUESTION_SPRING_DURATION / 4);
    flushFrame();
    const listShift = parseFloat(list.style.transform.slice('translateY('.length));
    const departingShift = parseFloat(departing.style.transform.slice('translateY('.length));
    expect(listShift).toBeGreaterThan(0);
    expect(listShift).toBeLessThan(500);
    expect(departingShift).toBeCloseTo(listShift - 500);
    expect(onEnd).not.toHaveBeenCalled();

    now.mockReturnValue(1000 + QUESTION_SPRING_DURATION);
    flushFrame();
    expect(list.style.transform).toBe('');
    expect(departing.isConnected).toBe(false);
    expect(onEnd).toHaveBeenCalledTimes(1);
  });

  it('ends a relay under way where it ends before it starts another', () => {
    const list = createList(0);
    const onEnd = jest.fn();

    measureRelayScroll(list, () => 2500, onEnd)!();
    const departing = list.nextElementSibling!;
    list.scrollTop = 0;
    measureRelayScroll(list, () => 2500)!();

    expect(departing.isConnected).toBe(false);
    expect(onEnd).toHaveBeenCalledTimes(1);
    expect(parent.querySelectorAll('[data-agent-departing-rows]')).toHaveLength(1);
  });

  it('ends a relay under way at once for a list that is reset', () => {
    const list = createList(0);
    const onEnd = jest.fn();

    measureRelayScroll(list, () => 2500, onEnd)!();
    finishRelayScroll(list);
    // The rows go in a mutation, as the reset may come while the frame's layout is read
    expect(parent.querySelector('[data-agent-departing-rows]')).not.toBeNull();
    flushFrame();

    expect(list.scrollTop).toBe(2500);
    expect(list.style.transform).toBe('');
    expect(parent.querySelector('[data-agent-departing-rows]')).toBeNull();
    expect(onEnd).toHaveBeenCalledTimes(1);
  });
});
