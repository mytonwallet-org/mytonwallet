import { preloadImage } from '../preloadImage';
import withCacheAsync from '../withCacheAsync';
import { type CardArtworkLayers, loadSvgCanvas } from './svgLayers';

import gramBase from '../../assets/cards/motion/gram-base.svg';
import gramBaseSvg from '../../assets/cards/motion/gram-base.svg?raw';
import myBase from '../../assets/cards/motion/my-base.webp';
import mySpot0 from '../../assets/cards/motion/my-spot0.svg?raw';
import mySpot1 from '../../assets/cards/motion/my-spot1.svg?raw';
import mySpot2 from '../../assets/cards/motion/my-spot2.svg?raw';

export function getDefaultCardImageUrl(isGram: boolean) {
  return isGram ? gramBase : myBase;
}

export const loadDefaultCardArtwork = withCacheAsync(async (isGram: boolean): Promise<CardArtworkLayers> => {
  // Release builds inline small SVG imports as `data:` URLs, and the CSP `connect-src` blocks fetching them.
  // So the SVGs are drawn from their source text, imported with `?raw`.
  const images = isGram ? [loadSvgCanvas(gramBaseSvg)]
    : [preloadImage(myBase), ...[mySpot0, mySpot1, mySpot2].map(loadSvgCanvas)];
  const [base, ...spots] = await Promise.all(images);

  return { base, spots, contrastColor: -1, contrastOpacity: 0 };
});
