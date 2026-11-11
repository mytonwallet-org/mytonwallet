import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentThreadListSkeleton from './AgentThreadListSkeleton';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
// Class names are their own keys, so that the shapes can be found by them
jest.mock('./AgentThreadList.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));

const ROOT_TOP = 100;
const SHAPE_STEP = 12;

describe('AgentThreadListSkeleton', () => {
  let container: HTMLDivElement;

  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
  });

  afterEach(() => {
    TeactDOM.render(undefined, container);
    container.remove();
    jest.restoreAllMocks();
  });

  it('raises the band of every shape by its distance from the top, so that one band runs down them all', async () => {
    jest.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function getRect(this: Element) {
      const index = Array.from(container.querySelectorAll('.skeletonShape')).indexOf(this);
      return { top: index === -1 ? ROOT_TOP : ROOT_TOP + index * SHAPE_STEP } as DOMRect;
    });

    TeactDOM.render(<AgentThreadListSkeleton isOpen />, container);
    await pause(20);

    const shapes = Array.from(container.querySelectorAll<HTMLElement>('.skeletonShape'));
    expect(shapes.length).toBeGreaterThan(1);
    shapes.forEach((shape, index) => {
      expect(shape.style.getPropertyValue('--skeleton-offset')).toBe(`${index * SHAPE_STEP}px`);
    });
  });
});
