import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import Media from './Media';

jest.mock('../../global', () => ({
  ...jest.requireActual('../../global'),
  withGlobal: () => (Component: unknown) => Component,
}));

const PICTURE_URL = 'https://example.com/picture.jpg';
// Styles and images share one stub here, which is the placeholder's image
const PLACEHOLDER_SRC = 'test-file-stub';

describe('a News picture in the media viewer', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows the placeholder of a media without an image once the picture fails to load', async () => {
    // The connected props are passed directly, as the viewer's state gives them
    const MediaWithState = Media as unknown as (props: Record<string, unknown>) => ReturnType<typeof Media>;
    TeactDOM.render(<MediaWithState mediaId="picture" isActive isPicture image={PICTURE_URL} alt="Picture" />, root);
    await pause(20);

    const picture = root.querySelector<HTMLImageElement>(`img[src="${PICTURE_URL}"]`)!;
    expect(picture).not.toBeNull();
    expect(root.querySelector(`img[src="${PLACEHOLDER_SRC}"]`)).toBeNull();

    picture.dispatchEvent(new Event('error'));
    await pause(20);

    expect(root.querySelector(`img[src="${PICTURE_URL}"]`)).toBeNull();
    expect(root.querySelector(`img[src="${PLACEHOLDER_SRC}"]`)).not.toBeNull();
  });
});
