import type { RgbaColor } from '../../../util/colors';

import { compositeCssColors, parseCssColor } from '../../../util/colors';

const REVEAL_EDGE_BACKGROUND_PROPERTY = '--agent-reveal-edge-background';
const TRANSPARENT_COLORS = new Set(['transparent', 'rgba(0, 0, 0, 0)', 'rgba(0,0,0,0)']);

export function getOpaqueBackgroundColor(element: HTMLElement) {
  let currentElement: HTMLElement | null = element;
  const translucentLayers: RgbaColor[] = [];
  let fallbackBackgroundColor: string | undefined;
  let edgeBackgroundColor: string | undefined;

  while (currentElement) {
    const computedStyle = getComputedStyle(currentElement);
    const currentRevealEdgeBackgroundColor = computedStyle.getPropertyValue(REVEAL_EDGE_BACKGROUND_PROPERTY).trim();
    if (!edgeBackgroundColor && currentRevealEdgeBackgroundColor) {
      edgeBackgroundColor = currentRevealEdgeBackgroundColor;
    } else if (
      edgeBackgroundColor
      && currentRevealEdgeBackgroundColor !== edgeBackgroundColor
    ) {
      break;
    }

    const backgroundColor = computedStyle.backgroundColor;
    if (backgroundColor && !TRANSPARENT_COLORS.has(backgroundColor)) {
      const parsedBackgroundColor = parseCssColor(backgroundColor);
      if (parsedBackgroundColor?.alpha === 1) {
        return compositeCssColors(parsedBackgroundColor, translucentLayers);
      }
      if (parsedBackgroundColor && parsedBackgroundColor.alpha > 0) {
        translucentLayers.push(parsedBackgroundColor);
      } else if (!fallbackBackgroundColor) {
        fallbackBackgroundColor = backgroundColor;
      }
    }

    currentElement = currentElement.parentElement;
  }

  const parsedRevealEdgeBackgroundColor = edgeBackgroundColor
    ? parseCssColor(edgeBackgroundColor)
    : undefined;
  if (parsedRevealEdgeBackgroundColor?.alpha === 1) {
    return compositeCssColors(parsedRevealEdgeBackgroundColor, translucentLayers);
  }

  return fallbackBackgroundColor ?? edgeBackgroundColor;
}
