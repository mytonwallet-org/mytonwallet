import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { copyTextToClipboard } from '../../util/clipboard';
import { pause } from '../../util/schedulers';

import StaticText from './StaticText';

const mockShowToast = jest.fn();

jest.mock('../../global', () => {
  const actual = jest.requireActual('../../global');
  return { ...actual, getActions: () => ({ ...actual.getActions(), showToast: mockShowToast }) };
});
jest.mock('../../util/clipboard', () => ({ copyTextToClipboard: jest.fn() }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('StaticText', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('copies a code block from the strip over it, which names its language', async () => {
    TeactDOM.render(<StaticText text={'Run it:\n\n```sh\nnpm test\n```'} areLinksEnabled />, root);
    await pause(20);

    const header = root.querySelector<HTMLButtonElement>('button[data-agent-code-copy]')!;
    expect(header.textContent).toBe('sh');
    expect(header.getAttribute('aria-label')).toBe('Copy');

    // The code and the text around it copy nothing
    root.querySelector('pre code')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    root.querySelector('p')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await pause(20);
    expect(copyTextToClipboard).not.toHaveBeenCalled();

    header.querySelector('span')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await pause(20);
    expect(copyTextToClipboard).toHaveBeenCalledWith('npm test');
    expect(mockShowToast).toHaveBeenCalledWith({ message: 'Copied.', icon: 'icon-copy' });
  });

  // An answer above a streaming one renders on every frame of the stream, with new lists of the same links
  it('keeps its nodes when it renders again with the same text', async () => {
    TeactDOM.render(<StaticText text="A finished answer" links={[]} areLinksEnabled />, root);
    await pause(20);
    const paragraph = root.querySelector('p');

    TeactDOM.render(<StaticText text="A finished answer" links={[]} areLinksEnabled />, root);
    await pause(20);

    expect(root.querySelector('p')).toBe(paragraph);
  });
});
