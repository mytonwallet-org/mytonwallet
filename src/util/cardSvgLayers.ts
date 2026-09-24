/** The card generator lays every card out in this coordinate system, and the motion math relies on it */
export const CARD_ARTWORK_WIDTH = 400;
export const CARD_ARTWORK_HEIGHT = 232;

/** Off-card color kept around each spot, so rotating it around the card center never reveals a cut edge */
export const CARD_SPOT_PADDING = 128;

/** The motion shader samples this many spot layers; any further spots stay in the base as still artwork */
export const CARD_MAX_SPOTS = 3;

/** The base is rasterized at the drawing-buffer cap, so the wave samples a sharp texture */
const BASE_RASTER_WIDTH = 800;

const FULL_CARD_PATH = /^M(?:400 0H0v232h400|0 0h400v232H0)z$/;

export interface CardSvgLayers {
  base: string;
  spots: string[];
  /** 1 for a white text-contrast gradient, 0 for a black one, -1 when the card has none */
  contrastColor: number;
  /** Strength of the overlay-blended part of the text-contrast gradient */
  contrastOpacity: number;
}

export interface CardArtworkLayers {
  base: HTMLImageElement;
  spots: HTMLImageElement[];
  contrastColor: number;
  contrastOpacity: number;
}

/**
 * Rasterizes the card artwork into the layers the motion shader animates separately.
 *
 * Returns `undefined` for artwork that is not the generator's SVG, so the caller can keep using
 * the already loaded image as the base.
 *
 * Even artwork without spots is rasterized here rather than taken from the page's `<img>`: Firefox
 * rasterizes an SVG `<img>` at its laid-out size, letterboxed to the SVG's aspect ratio, which leaves
 * transparent bands in the texture.
 */
export async function loadCardArtworkLayers(imageUrl: string): Promise<CardArtworkLayers | undefined> {
  const svgText = await (await fetch(imageUrl)).text();
  const layers = splitCardSvg(svgText);
  if (!layers) return undefined;

  const [base, ...spots] = await Promise.all([layers.base, ...layers.spots].map(loadSvgImage));

  return {
    base, spots, contrastColor: layers.contrastColor, contrastOpacity: layers.contrastOpacity,
  };
}

/**
 * Splits the generator's SVG the way the native renderer does: the background and texture stay in
 * the base, each blurred color spot becomes its own padded layer, and the two full-card gradients
 * that keep the balance text readable are described by their color and overlay strength, so the
 * shader can draw them above the moving spots.
 *
 * Premium cards blur their highlight with an ellipse, while standard spots are paths, which tells
 * a spot apart from a highlight that has to stay in the base.
 */
export function splitCardSvg(svgText: string): CardSvgLayers | undefined {
  const doc = new DOMParser().parseFromString(svgText, 'image/svg+xml');
  const root = doc.documentElement;
  if (root.localName !== 'svg' || root.getAttribute('viewBox') !== `0 0 ${CARD_ARTWORK_WIDTH} ${CARD_ARTWORK_HEIGHT}`) {
    return undefined;
  }

  const defs = Array.from(root.children).filter((element) => element.localName === 'defs');
  const content = Array.from(root.children).filter((element) => element.localName !== 'defs');
  if (!content.length) return undefined;

  const spotGroups = content.filter((element) => (
    element.localName === 'g' && element.hasAttribute('filter') && element.firstElementChild?.localName === 'path'
  )).slice(0, CARD_MAX_SPOTS);
  // The first full-card rectangle is the background, the later ones are the text-contrast gradients
  const contrastPaths = content.slice(1).filter((element) => (
    element.localName === 'path' && FULL_CARD_PATH.test(element.getAttribute('d') ?? '')
  ));
  const overlayPath = contrastPaths.find((element) => element.getAttribute('style')?.includes('mix-blend-mode'));
  const contrastOpacity = overlayPath?.hasAttribute('fill') ? Number(overlayPath.getAttribute('fill-opacity') ?? 1) : 0;
  const removed = new Set<Element>([...spotGroups, ...contrastPaths]);

  return {
    base: serialize(root, [...defs, ...content.filter((element) => !removed.has(element))], {
      viewBox: root.getAttribute('viewBox')!,
      width: BASE_RASTER_WIDTH,
      height: BASE_RASTER_WIDTH * CARD_ARTWORK_HEIGHT / CARD_ARTWORK_WIDTH,
    }),
    spots: spotGroups.map((group) => serialize(root, [...defs, group], {
      viewBox: `${-CARD_SPOT_PADDING} ${-CARD_SPOT_PADDING} ${CARD_ARTWORK_WIDTH + 2 * CARD_SPOT_PADDING} `
        + `${CARD_ARTWORK_HEIGHT + 2 * CARD_SPOT_PADDING}`,
      width: CARD_ARTWORK_WIDTH + 2 * CARD_SPOT_PADDING,
      height: CARD_ARTWORK_HEIGHT + 2 * CARD_SPOT_PADDING,
    })),
    contrastColor: contrastPaths.length ? getGradientColor(doc, contrastPaths) : -1,
    contrastOpacity,
  };
}

function serialize(
  root: Element,
  children: Element[],
  { viewBox, width, height }: { viewBox: string; width: number; height: number },
) {
  const svg = root.cloneNode(false) as Element;
  svg.setAttribute('viewBox', viewBox);
  svg.setAttribute('width', String(width));
  svg.setAttribute('height', String(height));
  svg.append(...children.map((child) => child.cloneNode(true)));

  return new XMLSerializer().serializeToString(svg);
}

/** The contrast gradients share one color, which their stops leave black by default */
function getGradientColor(doc: Document, contrastPaths: Element[]) {
  const gradientId = contrastPaths
    .map((element) => element.getAttribute('fill')?.match(/^url\(#(.+)\)$/)?.[1])
    .find(Boolean);
  const stopColor = gradientId
    ? doc.getElementById(gradientId)?.querySelector('stop')?.getAttribute('stop-color')
    : undefined;

  return stopColor && /^(#fff(fff)?|white)$/i.test(stopColor) ? 1 : 0;
}

async function loadSvgImage(svg: string) {
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  try {
    const image = new Image();
    image.src = url;
    await image.decode();

    return image;
  } finally {
    URL.revokeObjectURL(url);
  }
}
