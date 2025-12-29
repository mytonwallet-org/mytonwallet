import { type ElementRef, useLayoutEffect } from '../lib/teact/teact';
import { addExtraClass, removeExtraClass, setExtraStyles } from '../lib/teact/teact-dom';

import type { IAnchorPosition } from '../types';

import { requestForcedReflow } from '../lib/fasterdom/fasterdom';
import buildStyle from '../util/buildStyle';
import { clamp } from '../util/math';
import windowSize from '../util/windowSize';
import { useStateRef } from './useStateRef';

import styles from '../components/ui/Menu.module.scss';

interface Coordinates {
  x: number;
  y: number;
}

interface Bounds {
  width: number;
  height: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface MenuDimensions {
  width: number;
  height: number;
  marginTop: number;
}

interface GatherBoundsParams {
  getTriggerElement?: () => HTMLElement | undefined | null;
  getRootElement: () => HTMLElement | undefined | null;
  getMenuElement: () => HTMLElement | undefined | null;
  layout: Layout;
  anchor: IAnchorPosition;
}

interface PositionResult {
  positionX: 'left' | 'right';
  positionY: 'top' | 'bottom';
  coordinates: Coordinates;
  transformOrigin: Coordinates;
}

interface StaticPositionOptions {
  anchor?: IAnchorPosition;
  positionX?: 'left' | 'right';
  positionY?: 'top' | 'bottom';
  transformOriginX?: number;
  transformOriginY?: number;
  style?: string;
  bubbleStyle?: string;
}

interface DynamicPositionOptions {
  anchor: IAnchorPosition;
  getTriggerElement?: () => HTMLElement | undefined | null;
  getRootElement: () => HTMLElement | undefined | null;
  getMenuElement: () => HTMLElement | undefined | null;
  getLayout?: () => Layout;
  withMaxHeight?: boolean;
}

export type MenuPositionOptions = StaticPositionOptions | DynamicPositionOptions;

export interface Layout {
  extraPaddingX?: number;
  extraTopPadding?: number;
  extraMarginTop?: number;
  menuElMinWidth?: number;
  doNotCoverTrigger?: boolean;
  isCenteredHorizontally?: boolean;
  deltaX?: number;
  topShiftY?: number;
  shouldAvoidNegativePosition?: boolean;
  withPortal?: boolean;
  isDense?: boolean; //  Allows you to place the menu as close to the edges of the area as possible
  preferredPositionX?: 'left' | 'right';
  preferredPositionY?: 'top' | 'bottom';
}

const POSITIONING = {
  VISUAL_COMFORT_SPACE: 16,
  BOTTOM_MARGIN: 12,
  HORIZONTAL_OFFSET: 3,
  FALLBACK_X: 16,
  TRIGGER_OFFSET: 6,
} as const;

const EMPTY_RECT = {
  width: 0, left: 0, height: 0, top: 0, right: 0, bottom: 0,
};

export default function useMenuPosition(
  isOpen: boolean,
  containerRef: ElementRef<HTMLDivElement>,
  bubbleRef: ElementRef<HTMLDivElement>,
  options: MenuPositionOptions,
) {
  const optionsRef = useStateRef(options);

  useLayoutEffect(() => {
    if (!isOpen) return;

    const options2 = optionsRef.current;

    if (isDynamicPositionOptions(options2)) {
      requestForcedReflow(() => {
        const staticOptions = processDynamically(options2);

        return () => {
          applyStaticOptions(containerRef, bubbleRef, staticOptions);
        };
      });
    } else {
      applyStaticOptions(containerRef, bubbleRef, options2);
    }
  }, [isOpen, containerRef, bubbleRef, optionsRef]);
}

function applyStaticOptions(
  containerRef: ElementRef<HTMLDivElement>,
  bubbleRef: ElementRef<HTMLDivElement>,
  {
    anchor,
    positionX = 'left',
    positionY = 'top',
    transformOriginX,
    transformOriginY,
    style,
    bubbleStyle,
  }: StaticPositionOptions,
) {
  const containerEl = containerRef.current!;
  const bubbleEl = bubbleRef.current!;

  let finalStyle = style;
  if (anchor && !style) {
    finalStyle = `left: ${anchor.x}px; top: ${anchor.y}px`;
  }

  if (finalStyle) {
    containerEl.style.cssText = finalStyle;
  }

  if (bubbleStyle) {
    bubbleEl.style.cssText = bubbleStyle;
  }

  if (positionX) {
    removeExtraClass(bubbleEl, styles.left);
    removeExtraClass(bubbleEl, styles.right);
    addExtraClass(bubbleEl, styles[positionX]);
  }

  if (positionY) {
    removeExtraClass(bubbleEl, styles.top);
    removeExtraClass(bubbleEl, styles.bottom);
    addExtraClass(bubbleEl, styles[positionY]);
  }

  setExtraStyles(bubbleEl, {
    transformOrigin: [
      transformOriginX ? `${transformOriginX}px` : positionX,
      transformOriginY ? `${transformOriginY}px` : positionY,
    ].join(' '),
  });
}

function gatherBounds({
  getTriggerElement,
  getRootElement,
  getMenuElement,
  layout,
  anchor,
}: GatherBoundsParams): {
    triggerRect: DOMRect;
    rootRect: Bounds;
    menuDimensions: MenuDimensions;
  } {
  const triggerEl = getTriggerElement?.();
  const rootEl = getRootElement();
  const menuEl = getMenuElement();

  const { extraMarginTop = 0, menuElMinWidth = 0 } = layout;

  const triggerRect = triggerEl
    ? triggerEl.getBoundingClientRect()
    : { ...EMPTY_RECT, left: anchor.x, top: anchor.y, right: anchor.x, bottom: anchor.y } as DOMRect;
  const rootRect = rootEl ? rootEl.getBoundingClientRect() : EMPTY_RECT;

  rootRect.height -= windowSize.get().safeAreaBottom;

  let menuDimensions: MenuDimensions;
  if (menuEl) {
    const marginTop = parseInt(getComputedStyle(menuEl).marginTop, 10) + extraMarginTop;
    const { offsetWidth, offsetHeight } = menuEl;
    menuDimensions = {
      width: Math.max(offsetWidth, menuElMinWidth),
      height: offsetHeight + marginTop,
      marginTop,
    };
  } else {
    menuDimensions = { width: 0, height: 0, marginTop: 0 };
  }

  return { triggerRect, rootRect, menuDimensions };
}

function determineHorizontalPosition(
  anchor: Coordinates,
  rootRect: Bounds,
  menuWidth: number,
  deltaX: number,
  preferredPositionX: 'left' | 'right' = 'right',
): { positionX: 'left' | 'right'; x: number } {
  let x = anchor.x;
  let positionX: 'left' | 'right';

  if (preferredPositionX === 'right') {
    // Prefer left-leaning (opening leftward): try 'right' position first
    if (x - menuWidth >= rootRect.left + POSITIONING.VISUAL_COMFORT_SPACE) {
      positionX = 'right';
      x -= POSITIONING.HORIZONTAL_OFFSET;
    } else {
      // Fall back to right-leaning (opening rightward)
      positionX = 'left';
      x += POSITIONING.HORIZONTAL_OFFSET;
    }
  } else {
    // Prefer right-leaning (opening rightward): try 'left' position first
    if (x + menuWidth <= rootRect.right - POSITIONING.VISUAL_COMFORT_SPACE) {
      positionX = 'left';
      x += POSITIONING.HORIZONTAL_OFFSET;
    } else {
      // Fall back to left-leaning (opening leftward)
      positionX = 'right';
      x -= POSITIONING.HORIZONTAL_OFFSET;
    }
  }

  x += deltaX;

  return { positionX, x };
}

function determineVerticalPosition(
  anchor: Coordinates,
  triggerRect: DOMRect,
  rootRect: Bounds,
  menuHeight: number,
  layout: Layout,
): { positionY: 'top' | 'bottom'; y: number } {
  const {
    topShiftY = 0,
    extraTopPadding = 0,
    isDense = false,
    doNotCoverTrigger = false,
    preferredPositionY,
  } = layout;
  let y = anchor.y;
  let positionY: 'top' | 'bottom';

  // For `doNotCoverTrigger` we use the position relative to the trigger
  if (doNotCoverTrigger) {
    const hasSpaceBelow = triggerRect.bottom + POSITIONING.TRIGGER_OFFSET + menuHeight <= rootRect.bottom;
    const hasSpaceAbove = triggerRect.top - POSITIONING.TRIGGER_OFFSET - menuHeight >= rootRect.top;

    if (hasSpaceBelow && preferredPositionY !== 'bottom') {
      positionY = 'top';
      y = triggerRect.bottom + POSITIONING.TRIGGER_OFFSET;
    } else if (hasSpaceAbove) {
      positionY = 'bottom';
      y = triggerRect.top - POSITIONING.TRIGGER_OFFSET;
    } else {
      // If there is no room at the top or bottom, we use standard logic
      positionY = 'bottom';
      y = rootRect.top + rootRect.height;
    }
  } else {
    const yWithTopShift = y + topShiftY;
    const hasSpaceBelow = yWithTopShift + triggerRect.height + menuHeight < rootRect.height + rootRect.top;
    const hasSpaceAbove = y - triggerRect.height - menuHeight >= rootRect.top + extraTopPadding;

    if ((preferredPositionY === 'bottom' && hasSpaceAbove) || (!isDense && !hasSpaceBelow)) {
      positionY = 'bottom';
      if (!hasSpaceAbove) {
        y = rootRect.top + rootRect.height;
      }
    } else {
      positionY = 'top';
      y = yWithTopShift;
    }
  }

  return { positionY, y };
}

function applyBoundaryConstraints(
  coordinates: Coordinates,
  positionX: 'left' | 'right',
  triggerRect: DOMRect,
  rootRect: Bounds,
  menuDimensions: MenuDimensions,
  layout: Layout,
): Coordinates {
  const {
    shouldAvoidNegativePosition = false,
    withPortal = false,
    isDense = false,
    menuElMinWidth = 0,
    isCenteredHorizontally = false,
  } = layout;

  let { x, y } = coordinates;

  // Centering the menu with respect to the trigger
  if (isCenteredHorizontally) {
    x = triggerRect.left + (triggerRect.width - menuDimensions.width) / 2;

    // Check that the menu does not extend beyond the edges of the screen
    x = clamp(
      x,
      rootRect.left + POSITIONING.VISUAL_COMFORT_SPACE,
      rootRect.right - menuDimensions.width - POSITIONING.VISUAL_COMFORT_SPACE,
    );

    if (!withPortal) {
      y -= triggerRect.top;
    }
  } else {
    // Calculate relative position to trigger
    const leftWithPossibleNegative = Math.min(
      x - triggerRect.left,
      rootRect.width - menuDimensions.width - POSITIONING.VISUAL_COMFORT_SPACE,
    );

    // Apply horizontal constraints
    if (positionX === 'left') {
      if (withPortal || shouldAvoidNegativePosition) {
        x = Math.max(POSITIONING.VISUAL_COMFORT_SPACE, leftWithPossibleNegative);
      } else {
        x = leftWithPossibleNegative;
      }
    } else {
      x -= triggerRect.left;
    }

    // Apply portal positioning
    if (withPortal) {
      x += triggerRect.left;
      // For portal, Y coordinate should remain unchanged (already in viewport coordinates)
      // y stays as is
    } else {
      // For non-portal, convert from anchor coordinates to relative coordinates
      y -= triggerRect.top;
    }
  }

  // Apply dense mode constraints
  if (isDense) {
    x = Math.min(x, rootRect.width - menuDimensions.width - POSITIONING.VISUAL_COMFORT_SPACE);
    y = Math.min(y, rootRect.height - menuDimensions.height - POSITIONING.VISUAL_COMFORT_SPACE);
  }

  // Handle portal edge constraints
  if (withPortal && !isCenteredHorizontally) {
    if (positionX === 'left') {
      x = Math.min(x, rootRect.width - menuDimensions.width - POSITIONING.VISUAL_COMFORT_SPACE);
    } else {
      x = Math.max(x, POSITIONING.VISUAL_COMFORT_SPACE + menuDimensions.width);
    }
  }

  // Handle minimum width adjustments
  const addedXForMenuPositioning = menuElMinWidth ? Math.max(0,
    (menuElMinWidth - (menuDimensions.width - menuElMinWidth)) / 2) : 0;
  if (x - addedXForMenuPositioning < 0 && shouldAvoidNegativePosition) {
    x = addedXForMenuPositioning + POSITIONING.VISUAL_COMFORT_SPACE;
  }

  return { x, y };
}

function calculateTransformOrigin(
  anchor: Coordinates,
  finalCoordinates: Coordinates,
  positionResult: Pick<PositionResult, 'positionX' | 'positionY'>,
  triggerRect: DOMRect,
  menuDimensions: MenuDimensions,
  withPortal: boolean,
): Coordinates {
  const portalOffset = withPortal ? { x: triggerRect.left, y: triggerRect.top } : { x: 0, y: 0 };

  const offsetX = (anchor.x + portalOffset.x - triggerRect.left) - finalCoordinates.x;
  const offsetY = (anchor.y + portalOffset.y - triggerRect.top) - finalCoordinates.y - menuDimensions.marginTop;

  const transformOriginX = positionResult.positionX === 'left'
    ? offsetX
    : menuDimensions.width + offsetX;

  const transformOriginY = positionResult.positionY === 'bottom'
    ? menuDimensions.height + offsetY
    : offsetY;

  return { x: transformOriginX, y: transformOriginY };
}

function processDynamically(
  {
    anchor,
    getRootElement,
    getMenuElement,
    getTriggerElement,
    getLayout,
    withMaxHeight,
  }: DynamicPositionOptions,
) {
  const layout = getLayout?.() || {};

  const { triggerRect, rootRect, menuDimensions } = gatherBounds({
    getTriggerElement,
    getRootElement,
    getMenuElement,
    layout,
    anchor,
  });

  const { positionX, x } = determineHorizontalPosition(
    anchor,
    rootRect,
    menuDimensions.width,
    layout.deltaX || 0,
    layout.preferredPositionX,
  );

  const { positionY, y } = determineVerticalPosition(
    anchor,
    triggerRect,
    rootRect,
    menuDimensions.height,
    layout,
  );

  const finalCoordinates = applyBoundaryConstraints(
    { x, y },
    positionX,
    triggerRect,
    rootRect,
    menuDimensions,
    layout,
  );

  const transformOrigin = calculateTransformOrigin(
    anchor,
    finalCoordinates,
    { positionX, positionY },
    triggerRect,
    menuDimensions,
    layout.withPortal || false,
  );

  const style = buildStyle(
    `left: ${finalCoordinates.x}px`,
    `top: ${finalCoordinates.y}px`,
    `--menu-width: ${menuDimensions.width}px`,
    `--trigger-width: ${triggerRect.width}px`,
  );

  let bubbleStyle;
  if (withMaxHeight) {
    const menuMaxHeight = rootRect.height - POSITIONING.BOTTOM_MARGIN - menuDimensions.marginTop;
    bubbleStyle = `max-height: ${menuMaxHeight}px;`;
  }

  return {
    positionX,
    positionY,
    transformOriginX: transformOrigin.x,
    transformOriginY: transformOrigin.y,
    style,
    bubbleStyle,
  };
}

function isDynamicPositionOptions(options: MenuPositionOptions): options is DynamicPositionOptions {
  return 'getRootElement' in options;
}
