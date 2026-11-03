import { setPhase } from '../../../lib/fasterdom/stricterdom';
import { animateRevealEdges, clearRevealEdges, type RevealEdgeGroupState } from './streamingTextRevealEdge';

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
    container.style.backgroundColor = 'rgb(30, 30, 30)';
    const content = document.createElement('div');
    const layer = document.createElement('span');
    container.append(content, layer);
    document.body.appendChild(container);
    const groupsRef = { current: [] as RevealEdgeGroupState[] };
    const lifecycleRef = { current: 0 };
    setPhase('mutate');

    try {
      for (let index = 0; index < 40; index++) {
        const previousText = content.textContent!;
        for (let fragment = 0; fragment < fragmentCount; fragment++) {
          const span = document.createElement('span');
          span.textContent = 'word';
          content.appendChild(span);
        }
        animateRevealEdges(
          container, content, layer, previousText, content.textContent!, groupsRef, lifecycleRef, jest.fn(),
        );
        expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]').length).toBeLessThanOrEqual(24);
        expect(layer.querySelectorAll('*').length).toBeLessThanOrEqual(48);
      }

      expect(animate).toHaveBeenCalledTimes(40 * fragmentCount);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-cover]')).toHaveLength(24);
      expect(layer.querySelectorAll('[data-agent-streaming-reveal-edge-text]')).toHaveLength(24);
      expect(animate.mock.results[0].value.cancel).toHaveBeenCalledTimes(1);
      expect(animate.mock.results.at(-1)!.value.cancel).not.toHaveBeenCalled();
      expect(animate).toHaveBeenCalledWith(
        [
          { offset: 0, opacity: 0.16, filter: 'blur(0.3rem)', transform: 'translateY(0.08rem)' },
          { offset: 0.45, opacity: 0.72, filter: 'blur(0.08rem)', transform: 'translateY(0.02rem)' },
          { offset: 1, opacity: 1, filter: 'blur(0)', transform: 'translateY(0)' },
        ],
        { duration: 200, easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)', fill: 'forwards' },
      );
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
    container.style.backgroundColor = 'rgb(30, 30, 30)';
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
      expect(covers.map(({ textContent }) => textContent)).toEqual(['Ether', 'eum']);
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
});
