import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import AnimatedIconWithPreview from './AnimatedIconWithPreview';

let mockMarkAnimationReady: NoneToVoidFunction | undefined;

jest.mock('../../global', () => ({
  setGlobal: jest.fn(),
  withGlobal: () => (component: unknown) => component,
}));
jest.mock('./AnimatedIcon', () => ({
  __esModule: true,
  default: ({ onLoad }: { onLoad: NoneToVoidFunction }) => {
    mockMarkAnimationReady = onLoad;

    return undefined;
  },
}));

let root: HTMLDivElement;

beforeEach(() => {
  jest.useFakeTimers();
  root = document.createElement('div');
  document.body.append(root);
});

afterEach(async () => {
  TeactDOM.render(undefined, root);
  await jest.advanceTimersByTimeAsync(50);
  root.remove();
  jest.useRealTimers();
});

async function renderIcon(color?: string) {
  TeactDOM.render(<AnimatedIconWithPreview tgsUrl="icon.tgs" previewUrl="icon.png" color={color} />, root);
  await jest.advanceTimersByTimeAsync(50);
}

function getIsIconHidden() {
  return root.querySelector('[data-preview-url]')!.classList.contains('not-open');
}

it('keeps a ready icon visible when its color goes away', async () => {
  await renderIcon('#FF0000');
  mockMarkAnimationReady!();
  await jest.advanceTimersByTimeAsync(50);

  expect(getIsIconHidden()).toBe(false);

  await renderIcon();

  expect(getIsIconHidden()).toBe(false);
});

it('hides an uncolored icon until its preview or animation is ready', async () => {
  await renderIcon();

  expect(getIsIconHidden()).toBe(true);

  mockMarkAnimationReady!();
  await jest.advanceTimersByTimeAsync(50);

  expect(getIsIconHidden()).toBe(false);
});
