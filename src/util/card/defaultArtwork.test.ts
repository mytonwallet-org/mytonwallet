import { preloadImage } from '../preloadImage';
import { loadDefaultCardArtwork } from './defaultArtwork';
import { loadSvgCanvas } from './svgLayers';

jest.mock('../preloadImage', () => ({ preloadImage: jest.fn() }));
jest.mock('./svgLayers', () => ({ loadSvgCanvas: jest.fn() }));

it('loads and shares My layers without fetching inline SVG URLs', async () => {
  const originalFetch = window.fetch;
  const fetch = jest.fn().mockRejectedValue(new TypeError('CSP blocked'));
  window.fetch = fetch;

  const base = document.createElement('img');
  const spot = document.createElement('canvas');
  jest.mocked(preloadImage).mockResolvedValue(base);
  jest.mocked(loadSvgCanvas).mockResolvedValue(spot);

  const first = loadDefaultCardArtwork(false);
  const second = loadDefaultCardArtwork(false);
  expect(await first).toEqual({ base, spots: [spot, spot, spot], contrastColor: -1, contrastOpacity: 0 });
  expect(await second).toBe(await first);
  expect(preloadImage).toHaveBeenCalledTimes(1);
  expect(loadSvgCanvas).toHaveBeenCalledTimes(3);
  expect(fetch).not.toHaveBeenCalled();
  window.fetch = originalFetch;
});

it('allows Gram layers to recover after a decode failure instead of caching the rejection', async () => {
  const base = document.createElement('canvas');
  jest.mocked(loadSvgCanvas).mockRejectedValueOnce(new Error('Decode failed')).mockResolvedValue(base);
  await expect(loadDefaultCardArtwork(true)).rejects.toThrow('Decode failed');

  await expect(loadDefaultCardArtwork(true)).resolves.toEqual({
    base, spots: [], contrastColor: -1, contrastOpacity: 0,
  });
});
