import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import type { ApiNft } from '../api/types';

import { getCachedImageUrl } from '../util/getCachedImageUrl';
import useCardArtwork, { preloadCardArtworks, useCardArtworkUrl } from './useCardArtwork';

jest.mock('../util/getCachedImageUrl', () => ({ getCachedImageUrl: jest.fn() }));

const DEFAULT_URL = 'test-file-stub';

function nft(id: number) {
  return { address: `card${id}`, metadata: { mtwCardId: id } } as unknown as ApiNft;
}

function Probe({ cardNft }: { cardNft?: ApiNft }) {
  const { nft: shownNft, imageUrl } = useCardArtwork(cardNft);

  return (
    <div
      data-nft={shownNft?.address ?? 'default'}
      data-url={imageUrl ?? ''}
      data-type={shownNft?.metadata.mtwCardType ?? ''}
    />
  );
}

function Picture({ cardNft }: { cardNft: ApiNft }) {
  const imageUrl = useCardArtworkUrl(cardNft);

  return <img src={imageUrl} alt="" />;
}

describe('useCardArtwork', () => {
  let root: HTMLDivElement;
  let decodes: Map<string, { resolve: NoneToVoidFunction; reject: NoneToVoidFunction }>;
  const revokeObjectURL = jest.fn();

  function shown() {
    const probe = root.querySelector('div')!;

    return [probe.dataset.nft, probe.dataset.url];
  }

  async function render(cardNft?: ApiNft) {
    TeactDOM.render(<Probe cardNft={cardNft} />, root);
    await jest.advanceTimersByTimeAsync(50);
  }

  async function finishDecode(url: string, isFailed = false) {
    const decode = decodes.get(url)!;
    if (isFailed) decode.reject();
    else decode.resolve();
    await jest.advanceTimersByTimeAsync(50);
  }

  beforeEach(() => {
    jest.useFakeTimers();
    root = document.createElement('div');
    document.body.append(root);
    decodes = new Map();
    revokeObjectURL.mockClear();
    URL.revokeObjectURL = revokeObjectURL;
    jest.mocked(getCachedImageUrl).mockImplementation((src) => Promise.resolve(`blob:${src.split('/').pop()}`));

    HTMLImageElement.prototype.decode = function decode(this: HTMLImageElement) {
      return new Promise<void>((resolve, reject) => {
        decodes.set(this.getAttribute('src')!, { resolve, reject: () => reject(new Error('broken')) });
      });
    };
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(50);
    root.remove();
    jest.useRealTimers();
  });

  it('keeps the previous artwork until the next one is decoded', async () => {
    await render();
    expect(shown()).toEqual(['default', DEFAULT_URL]);

    await render(nft(1));
    expect(shown()).toEqual(['default', DEFAULT_URL]);

    await finishDecode('blob:1.svg');
    expect(shown()).toEqual(['card1', 'blob:1.svg']);

    await render(nft(2));
    expect(shown()).toEqual(['card1', 'blob:1.svg']);
    expect(revokeObjectURL).not.toHaveBeenCalled();

    await finishDecode('blob:2.svg');
    expect(shown()).toEqual(['card2', 'blob:2.svg']);
    expect(revokeObjectURL).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(1000);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:1.svg');
    expect(revokeObjectURL).not.toHaveBeenCalledWith('blob:2.svg');
  });

  it('never shows an artwork replaced before it was decoded', async () => {
    await render(nft(3));
    expect(shown()).toEqual(['default', DEFAULT_URL]);

    await render(nft(4));
    await finishDecode('blob:3.svg');
    expect(shown()).toEqual(['default', DEFAULT_URL]);

    await finishDecode('blob:4.svg');
    expect(shown()).toEqual(['card4', 'blob:4.svg']);
  });

  it('shows an already decoded artwork from the first frame of a remounted card', async () => {
    await render(nft(5));
    await finishDecode('blob:5.svg');
    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(50);
    decodes.clear();

    TeactDOM.render(<Probe cardNft={nft(5)} />, root);
    expect(shown()).toEqual(['card5', 'blob:5.svg']);
    await jest.advanceTimersByTimeAsync(50);
    expect(shown()).toEqual(['card5', 'blob:5.svg']);
    expect(decodes.size).toBe(0);
  });

  it('applies a refreshed NFT with the same image without decoding it again', async () => {
    await render(nft(6));
    await finishDecode('blob:6.svg');
    decodes.clear();

    await render({ ...nft(6), metadata: { mtwCardId: 6, mtwCardType: 'gold' } } as unknown as ApiNft);
    expect(shown()).toEqual(['card6', 'blob:6.svg']);
    expect(root.querySelector('div')!.dataset.type).toBe('gold');
    expect(decodes.size).toBe(0);
  });

  it('shows the default artwork when the image is broken', async () => {
    await render(nft(7));
    await finishDecode('blob:7.svg', true);
    expect(shown()).toEqual(['default', DEFAULT_URL]);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:7.svg');
  });

  it('keeps the artwork of an account card after its card unmounts', async () => {
    preloadCardArtworks([nft(8)]);
    await jest.advanceTimersByTimeAsync(50);
    await finishDecode('blob:8.svg');
    await render(nft(8));
    expect(shown()).toEqual(['card8', 'blob:8.svg']);

    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(2000);
    expect(revokeObjectURL).not.toHaveBeenCalled();
  });

  it('shares one image between a card and its picture and releases it once both are gone', async () => {
    TeactDOM.render(<><Probe cardNft={nft(9)} /><Picture cardNft={nft(9)} /></>, root);
    await jest.advanceTimersByTimeAsync(50);
    await finishDecode('blob:9.svg');
    expect(shown()).toEqual(['card9', 'blob:9.svg']);
    expect(root.querySelector('img')!.getAttribute('src')).toBe('blob:9.svg');
    expect(jest.mocked(getCachedImageUrl).mock.calls.filter(([src]) => src.endsWith('/9.svg'))).toHaveLength(1);

    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(1000);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:9.svg');
  });
});
