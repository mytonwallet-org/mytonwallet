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
});
