import { setPhase } from '../../../lib/fasterdom/stricterdom';
import { STREAMED_CHARACTER_DURATION_MS } from './streamingTextAppearance';
import { animateRevealEdges, clearRevealEdges, type RevealEdgeGroupState } from './streamingTextRevealEdge';

const mockMeasureCallbacks: NoneToVoidFunction[] = [];
jest.mock('../../../lib/fasterdom/fasterdom', () => ({
  ...jest.requireActual('../../../lib/fasterdom/fasterdom'),
  requestMeasure: (callback: NoneToVoidFunction) => mockMeasureCallbacks.push(callback),
}));
// Each colour has its highlights by the sample of the settling, named after the colour and the dark theme, which hold
// their ranges here
const mockHighlights = new Map<string, Set<Range>>();
let mockIsTextHighlightSupported = true;
jest.mock('./streamingTextHighlights', () => ({
  getIsTextHighlightSupported: () => mockIsTextHighlightSupported,
  getStreamedTextHighlightNames: (color: string, isDark: boolean) => (
    color ? Array.from({ length: 27 }, (_, index) => `${isDark ? 'dark:' : ''}${color}/${index}`) : undefined
  ),
  addHighlightRange: (name: string, range: Range) => {
    if (!mockHighlights.has(name)) mockHighlights.set(name, new Set());
    mockHighlights.get(name)!.add(range);
  },
  deleteHighlightRange: (name: string, range: Range) => mockHighlights.get(name)?.delete(range),
}));

describe('streaming reveal edge pool', () => {
  it.each([1, 2, 3])('bounds DOM growth for groups of %s fragments while animations are running', (fragmentCount) => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animate = jest.fn(() => ({ cancel: jest.fn() }) as unknown as Animation);
    Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: animate });
    jest.spyOn(document, 'createRange').mockImplementation(() => ({
      setStart: jest.fn(),
      setEnd: jest.fn(),
      getClientRects: () => [new DOMRect(0, 0, 100, 20)],
    }) as unknown as Range);
    const container = document.createElement('div');
    const content = document.createElement('div');
    const layer = document.createElement('span');
    container.append(content, layer);
    document.body.appendChild(container);
    const groupsRef = { current: [] as RevealEdgeGroupState[] };
    const lifecycleRef = { current: 0 };
    setPhase('mutate');

    try {
      for (let index = 0; index < 100; index++) {
        const previousText = content.textContent!;
        for (let fragment = 0; fragment < fragmentCount; fragment++) {
          const span = document.createElement('span');
          span.textContent = 'word';
          content.appendChild(span);
        }
        animateRevealEdges(
          container, content, layer, previousText, content.textContent!, groupsRef, lifecycleRef, jest.fn(),
        );
        expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]').length).toBeLessThanOrEqual(84);
        expect(layer.querySelectorAll('*').length).toBeLessThanOrEqual(168);
      }

      expect(animate).toHaveBeenCalledTimes(100 * fragmentCount);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]')).toHaveLength(84);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-text]')).toHaveLength(84);
      expect(animate.mock.results[0].value.cancel).toHaveBeenCalledTimes(1);
      expect(animate.mock.results.at(-1)!.value.cancel).not.toHaveBeenCalled();
      // A character settles in its own colour over 0.65 s, as on iOS
      expect(animate).toHaveBeenCalledWith(expect.any(Array), { duration: 650, fill: 'forwards' });
    } finally {
      clearRevealEdges(groupsRef);
      setPhase('measure');
      container.remove();
      jest.restoreAllMocks();
      if (originalAnimate) {
        Object.defineProperty(Element.prototype, 'animate', originalAnimate);
      } else {
        Reflect.deleteProperty(Element.prototype, 'animate');
      }
    }
  });

  it('moves the covers of a word that wraps to the next line, at the point of their animation', () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animate = jest.fn(() => ({ cancel: jest.fn(), currentTime: 0 }) as unknown as Animation);
    Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: animate });
    let lineTop = 0;
    jest.spyOn(document, 'createRange').mockImplementation(() => ({
      setStart: jest.fn(),
      setEnd: jest.fn(),
      getClientRects: () => [new DOMRect(200, lineTop, 10, 20)],
    }) as unknown as Range);
    const container = document.createElement('div');
    const content = document.createElement('div');
    const layer = document.createElement('span');
    container.append(content, layer);
    document.body.appendChild(container);
    const groupsRef = { current: [] as RevealEdgeGroupState[] };
    const lifecycleRef = { current: 0 };
    setPhase('mutate');

    try {
      content.textContent = 'Ether';
      animateRevealEdges(container, content, layer, '', 'Ether', groupsRef, lifecycleRef, jest.fn());
      const firstCover = layer.querySelector<HTMLElement>('[data-agent-streaming-reveal-edge-cover]')!;
      expect(firstCover.style.top).toBe('0px');
      (animate.mock.results[0].value as { currentTime: number }).currentTime = 120;

      lineTop = 20;
      content.textContent = 'Ethereum';
      animateRevealEdges(container, content, layer, 'Ether', 'Ethereum', groupsRef, lifecycleRef, jest.fn());

      const covers = Array.from(layer.querySelectorAll<HTMLElement>('[data-agent-streaming-reveal-edge-cover]'));
      expect(firstCover.isConnected).toBe(false);
      expect(covers.map(({ style }) => style.top)).toEqual(['20px', '20px']);
      expect(covers.map(getCoverText)).toEqual(['Ether', 'eum']);
      // The copies hold no text of their own, so the answer's text shows once in the page's text
      expect(layer.textContent).toBe('');
      expect(animate.mock.results[0].value.cancel).toHaveBeenCalled();
      expect((animate.mock.results[1].value as { currentTime: number }).currentTime).toBe(120);
    } finally {
      clearRevealEdges(groupsRef);
      setPhase('measure');
      container.remove();
      jest.restoreAllMocks();
      if (originalAnimate) {
        Object.defineProperty(Element.prototype, 'animate', originalAnimate);
      } else {
        Reflect.deleteProperty(Element.prototype, 'animate');
      }
    }
  });

  it('colours the revealed text itself where it stands, in time with the glow its copy alone draws', () => {
    const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
    const animation = { cancel: jest.fn(), currentTime: 0 } as unknown as Animation;
    const animate = jest.fn(() => animation);
    Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: animate });
    const ranges: { setStart: jest.Mock; setEnd: jest.Mock }[] = [];
    jest.spyOn(document, 'createRange').mockImplementation(() => {
      const range = { setStart: jest.fn(), setEnd: jest.fn(), getClientRects: () => [new DOMRect(200, 0, 10, 20)] };
      ranges.push(range);
      return range as unknown as Range;
    });
    const container = document.createElement('div');
    const content = document.createElement('div');
    content.style.color = 'rgb(1, 2, 3)';
    const layer = document.createElement('span');
    container.append(content, layer);
    document.body.appendChild(container);
    const groupsRef = { current: [] as RevealEdgeGroupState[] };
    const onSettled = jest.fn();
    setPhase('mutate');

    try {
      content.textContent = 'Ether';
      animateRevealEdges(container, content, layer, '', 'Ether', groupsRef, { current: 0 }, onSettled);

      // The text node's letters themselves take the first colour of their settling
      const textNode = content.firstChild;
      const coloring = ranges.find(({ setEnd }) => setEnd.mock.calls.length && setEnd.mock.calls[0][1] === 5)!;
      expect(coloring.setStart).toHaveBeenCalledWith(textNode, 0);
      expect(mockHighlights.get('rgb(1, 2, 3)/0')).toEqual(new Set([coloring]));
      // The copy over them shows nothing but its glow
      const copy = layer.querySelector<HTMLElement>('[data-agent-streaming-reveal-edge-text]')!;
      expect(copy.style.color).toBe('');
      const [[keyframes, timing]] = animate.mock.calls as unknown as [Keyframe[], KeyframeAnimationOptions][];
      expect(keyframes.every((keyframe) => 'textShadow' in keyframe && !('color' in keyframe))).toBe(true);
      expect(timing).toEqual({ duration: STREAMED_CHARACTER_DURATION_MS, fill: 'forwards' });

      // The colour steps on with the glow, 25 ms a sample
      (animation as { currentTime: number }).currentTime = 60;
      mockMeasureCallbacks.splice(0).forEach((callback) => callback());
      expect(mockHighlights.get('rgb(1, 2, 3)/0')!.size).toBe(0);
      expect(mockHighlights.get('rgb(1, 2, 3)/2')).toEqual(new Set([coloring]));

      // The text is in its own colour once the glow has settled
      animation.onfinish!({} as AnimationPlaybackEvent);
      expect(mockHighlights.get('rgb(1, 2, 3)/2')!.size).toBe(0);
      expect(groupsRef.current).toHaveLength(0);
      expect(onSettled).toHaveBeenCalledTimes(1);
      mockMeasureCallbacks.splice(0).forEach((callback) => callback());
      expect(mockMeasureCallbacks).toHaveLength(0);
    } finally {
      clearRevealEdges(groupsRef);
      setPhase('measure');
      container.remove();
      jest.restoreAllMocks();
      if (originalAnimate) {
        Object.defineProperty(Element.prototype, 'animate', originalAnimate);
      } else {
        Reflect.deleteProperty(Element.prototype, 'animate');
      }
    }
  });

  it('reads the content once a pass however many groups settle, and colours anew only replaced text', () => {
    const scene = setUpScene();
    const createTreeWalker = jest.spyOn(document, 'createTreeWalker');

    try {
      const ether = scene.appendText('Ether');
      scene.reveal('', 'Ether');
      const [etherColoring] = mockHighlights.get('rgb(1, 2, 3)/0')!;
      expect(etherColoring.startContainer).toBe(ether);

      for (const word of ['eum', ' is', ' a', ' chain']) {
        const previousText = scene.content.textContent!;
        scene.appendText(word);
        createTreeWalker.mockClear();
        scene.reveal(previousText, scene.content.textContent!);
        expect(createTreeWalker).toHaveBeenCalledTimes(1);
      }
      // The text under the first group's colours stayed, so its colours did too
      expect(scene.groupsRef.current).toHaveLength(5);
      expect(mockHighlights.get('rgb(1, 2, 3)/0')!.has(etherColoring)).toBe(true);

      // A replaced text node takes the colours anew
      const replacedEther = document.createTextNode('Ether');
      scene.content.replaceChild(replacedEther, ether);
      const previousText = scene.content.textContent!;
      scene.appendText('!');
      scene.reveal(previousText, scene.content.textContent!);
      const colorings = Array.from(mockHighlights.get('rgb(1, 2, 3)/0')!);
      expect(colorings).not.toContain(etherColoring);
      expect(colorings.some(({ startContainer }) => startContainer === replacedEther)).toBe(true);
    } finally {
      scene.tearDown();
    }
  });

  it('leaves the covers of sharp characters where they are as their text wraps anew', () => {
    const scene = setUpScene();

    try {
      scene.appendText('Ether');
      scene.reveal('', 'Ether');
      const firstCover = scene.layer.querySelector<HTMLElement>('[data-agent-streaming-reveal-edge-cover]')!;
      // The first group's characters are sharp, so its cover shows nothing
      (scene.animate.mock.results[0].value as { currentTime: number }).currentTime = 200;

      scene.lineTop = 20;
      scene.appendText('eum');
      scene.reveal('Ether', 'Ethereum');

      expect(firstCover.isConnected).toBe(true);
      expect(firstCover.style.top).toBe('0px');
      expect(scene.animate).toHaveBeenCalledTimes(2);
    } finally {
      scene.tearDown();
    }
  });

  it('takes the other theme\'s colours as the theme changes while the text settles', () => {
    const scene = setUpScene();

    try {
      scene.appendText('Ether');
      scene.reveal('', 'Ether');
      const [coloring] = mockHighlights.get('rgb(1, 2, 3)/0')!;

      document.documentElement.classList.add('theme-dark');
      (scene.animate.mock.results[0].value as { currentTime: number }).currentTime = 60;
      mockMeasureCallbacks.splice(0).forEach((callback) => callback());

      expect(mockHighlights.get('rgb(1, 2, 3)/0')!.size).toBe(0);
      expect(mockHighlights.get('rgb(1, 2, 3)/2')).toBeUndefined();
      expect(mockHighlights.get('dark:rgb(1, 2, 3)/2')).toEqual(new Set([coloring]));
    } finally {
      document.documentElement.classList.remove('theme-dark');
      scene.tearDown();
    }
  });

  it('hides the text under a copy that shows the whole character where the browser has no CSS highlights', () => {
    mockIsTextHighlightSupported = false;
    const scene = setUpScene();
    scene.container.style.setProperty('--agent-reveal-edge-background', 'rgb(12, 34, 56)');

    try {
      scene.appendText('Ether');
      scene.reveal('', 'Ether');

      const cover = scene.layer.querySelector<HTMLElement>('[data-agent-streaming-reveal-edge-cover]')!;
      expect(cover.style.backgroundColor).toBe('rgb(12, 34, 56)');
      expect(mockHighlights.size).toBe(0);
      const [[keyframes, timing]] = scene.animate.mock.calls as unknown as [Keyframe[], KeyframeAnimationOptions][];
      expect(keyframes.every((keyframe) => 'textShadow' in keyframe && 'color' in keyframe)).toBe(true);
      expect(keyframes[0].color).not.toBe(keyframes.at(-1)!.color);
      expect(keyframes.at(-1)!.color).toBe('rgba(1, 2, 3, 1)');
      expect(timing).toEqual({ duration: STREAMED_CHARACTER_DURATION_MS, fill: 'forwards' });

      // The copy shows the character until it settles, so it follows its text all the while
      (scene.animate.mock.results[0].value as { currentTime: number }).currentTime = 400;
      scene.lineTop = 20;
      scene.appendText('eum');
      scene.reveal('Ether', 'Ethereum');
      expect(cover.isConnected).toBe(false);
      const covers = Array.from(scene.layer.querySelectorAll<HTMLElement>('[data-agent-streaming-reveal-edge-cover]'));
      expect(covers.map(({ style }) => style.top)).toEqual(['20px', '20px']);
      expect((scene.animate.mock.results[1].value as { currentTime: number }).currentTime).toBe(400);
    } finally {
      mockIsTextHighlightSupported = true;
      scene.tearDown();
    }
  });
});

// A content of real text nodes, in `rgb(1, 2, 3)`, whose letters stand on one line at `lineTop`
function setUpScene() {
  // The colours of earlier tests have gone, so their loop ends
  mockMeasureCallbacks.splice(0).forEach((callback) => callback());
  mockHighlights.clear();
  const originalAnimate = Object.getOwnPropertyDescriptor(Element.prototype, 'animate');
  const animate = jest.fn(() => ({ cancel: jest.fn(), currentTime: 0 }) as unknown as Animation);
  Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: animate });
  const createRange = document.createRange.bind(document);
  const container = document.createElement('div');
  const content = document.createElement('div');
  content.style.color = 'rgb(1, 2, 3)';
  const layer = document.createElement('span');
  container.append(content, layer);
  document.body.appendChild(container);
  const groupsRef = { current: [] as RevealEdgeGroupState[] };
  const scene = {
    animate,
    container,
    content,
    layer,
    groupsRef,
    lineTop: 0,
    appendText(text: string) {
      const node = document.createTextNode(text);
      content.appendChild(node);
      return node;
    },
    reveal(previousText: string, currentText: string) {
      animateRevealEdges(container, content, layer, previousText, currentText, groupsRef, { current: 0 }, jest.fn());
    },
    tearDown() {
      clearRevealEdges(groupsRef);
      setPhase('measure');
      container.remove();
      jest.restoreAllMocks();
      if (originalAnimate) {
        Object.defineProperty(Element.prototype, 'animate', originalAnimate);
      } else {
        Reflect.deleteProperty(Element.prototype, 'animate');
      }
    },
  };
  jest.spyOn(document, 'createRange').mockImplementation(() => {
    const range = createRange();
    range.getClientRects = () => [new DOMRect(200, scene.lineTop, 10, 20)] as unknown as DOMRectList;
    return range;
  });
  setPhase('mutate');

  return scene;
}

function getCoverText(cover: HTMLElement) {
  const copy = cover.querySelector<HTMLElement>('[data-agent-streaming-reveal-edge-text]')!;
  return copy.dataset.agentStreamingRevealEdgeText;
}
