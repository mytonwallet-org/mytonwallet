import type { ElementRef } from '../../lib/teact/teact';

import type { Point } from './surfaceMotion';

export interface CardMotionFrame {
  press: readonly number[];
  light: { x: number; y: number; opacity: number };
  /** Where the finger or mouse is on the card, from -1 to 1 on each axis */
  pointer?: readonly [number, number];
  isPlaying: boolean;
  isHovering?: boolean;
}

/** Shared by the layers of one card, so the press hook, the surface and the privacy fields can reach each other */
export interface CardController {
  cardRef: ElementRef<HTMLDivElement>;
  motion?: CardMotionFrame;
  /** Where the latest privacy toggle was tapped, in card coordinates */
  origin?: Point;
  /** Set while the surface is mounted, so motion changes can restart its frame loop */
  wakeSurface?: NoneToVoidFunction;
  /** The visible card face for the privacy fields to blur, or nothing while no artwork is loaded */
  getBackdrop?: () => HTMLCanvasElement | HTMLImageElement | undefined;
}
