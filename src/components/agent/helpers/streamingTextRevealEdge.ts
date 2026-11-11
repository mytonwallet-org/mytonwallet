import type { RefObject } from '../../../lib/teact/teact';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import { MAXIMUM_INITIAL_REVEAL_GRAPHEMES } from '../../../util/agent/TextRevealController';
import { animate } from '../../../util/animation';
import segmentGraphemes from '../../../util/segmentGraphemes';
import { getIsDarkTheme } from './agentGlowPalette';
import {
  getStreamedCharacterCopyKeyframes,
  getStreamedCharacterGlowKeyframes,
  STREAMED_CHARACTER_DURATION_MS,
  STREAMED_CHARACTER_GLOW_DURATION_MS,
  STREAMED_CHARACTER_SAMPLE_INTERVAL_MS,
} from './streamingTextAppearance';
import { getOpaqueBackgroundColor } from './streamingTextColor';
import { measureStreamingTextDom, mutateStreamingTextDom } from './streamingTextDom';
import {
  addHighlightRange,
  deleteHighlightRange,
  getIsTextHighlightSupported,
  getStreamedTextHighlightNames,
} from './streamingTextHighlights';

import styles from '../StreamingText.module.scss';

// Enough for the groups a reveal starts, one a frame, while a character settles, at 120 frames a second
const MAXIMUM_REVEAL_EDGE_GROUPS = 84;
const MAXIMUM_REVEAL_EDGE_ELEMENTS = 168;
const SAME_LINE_TOLERANCE_PX = 0.5;
// The sample of a character's settling in its own colour
const LAST_SAMPLE_INDEX = Math.round(STREAMED_CHARACTER_DURATION_MS / STREAMED_CHARACTER_SAMPLE_INTERVAL_MS);

interface RevealEdgeFragmentState {
  coverElement: HTMLSpanElement;
  animation: Animation;
  left: number;
  top: number;
  width: number;
  height: number;
}

/**
 * A piece of revealed text, in one of the highlights of its colour, the one of the sample its settling has reached. A
 * colour that cannot be read has no highlights, and its range only marks the text it lies on.
 */
interface RevealEdgeColoring {
  range: Range;
  highlightNames?: string[];
}

/**
 * Revealed text that comes in as on iOS. The text itself takes the Agent's colours where it stands, through CSS
 * highlights, so its letters never move as they settle, and covers over it draw only its glow, as the shadow of
 * copies that show nothing else. Where the browser has no CSS highlights, a cover hides the text instead, and the copy
 * over it shows the whole character, its colours and its glow.
 */
export interface RevealEdgeGroupState {
  fragments: RevealEdgeFragmentState[];
  colorings: RevealEdgeColoring[];
  // The theme the colours were taken in
  isDark: boolean;
  sampleIndex: number;
  // Where the revealed text lies in the content, so that its colours and covers can follow it when the lines wrap anew
  startOffset: number;
  text: string;
}

interface MeasuredRevealEdgeGroup {
  group: RevealEdgeGroupState;
  // The colours of its text, which take it anew where the text nodes under them were replaced or the theme changed
  coloring?: PreparedRevealEdgeColoring[];
  // Its text lies elsewhere while its covers still show, so they go with it; none at all removes the group
  fragments?: PreparedRevealEdgeFragment[];
}

/** What one pass reads of the content, shared by the groups it measures */
interface RevealEdgeMeasurement {
  containerRect: DOMRect;
  textNodes: RevealEdgeTextNode[];
  colorsByElement: Map<HTMLElement, string>;
  isColoredInPlace: boolean;
}

interface RevealEdgeTextNode {
  node: Text;
  // Where it starts in the content's text
  startOffset: number;
}

interface RevealEdgeTextPiece {
  node: Text;
  startOffset: number;
  endOffset: number;
}

interface PreparedRevealEdgeColoring extends RevealEdgeTextPiece {
  color: string;
}

interface RevealEdgeVisualFragment {
  rectangle: DOMRect;
  text: string;
  sourceElement: HTMLElement;
}

interface RevealEdgeTypography {
  direction: string;
  fontFamily: string;
  fontFeatureSettings: string;
  fontSize: string;
  fontStretch: string;
  fontStyle: string;
  fontVariant: string;
  fontWeight: string;
  letterSpacing: string;
  lineHeight: string;
  textAlign: string;
  textDecoration: string;
  textTransform: string;
  wordSpacing: string;
}

interface PreparedRevealEdgeFragment {
  // The cover's opaque colour, which hides the text under the copy where the text cannot take its colours itself
  backgroundColor?: string;
  color: string;
  direction: string;
  height: number;
  left: number;
  text: string;
  top: number;
  typography: RevealEdgeTypography;
  width: number;
}

// The groups whose text is coloured, which one loop takes through the samples of their settling
const coloredGroups = new Set<RevealEdgeGroupState>();
let isColoring = false;

export function animateRevealEdges(
  container: HTMLElement | undefined,
  content: HTMLElement,
  layer: HTMLSpanElement | undefined,
  previousTextContent: string,
  currentTextContent: string,
  groupsRef: RefObject<RevealEdgeGroupState[]>,
  lifecycleGenerationRef: RefObject<number>,
  onSettled: NoneToVoidFunction,
) {
  if (
    !container
    || !layer
    || typeof document.createRange !== 'function'
    || typeof document.createTreeWalker !== 'function'
    || typeof NodeFilter === 'undefined'
  ) {
    return;
  }

  const edge = getRevealEdge(previousTextContent, currentTextContent);
  if (!edge && !groupsRef.current.length) return;

  const isDark = getIsDarkTheme();
  const { prepared, measuredGroups } = measureStreamingTextDom(() => {
    const groups = groupsRef.current;
    const fromOffset = Math.min(edge?.startOffset ?? Infinity, ...groups.map(({ startOffset }) => startOffset));
    const measurement: RevealEdgeMeasurement = {
      containerRect: container.getBoundingClientRect(),
      textNodes: collectRevealEdgeTextNodes(content, fromOffset),
      colorsByElement: new Map(),
      isColoredInPlace: getIsTextHighlightSupported(),
    };

    return {
      prepared: edge && prepareRevealEdgeGroup(measurement, edge, currentTextContent.length),
      measuredGroups: measureRevealEdgeGroups(measurement, currentTextContent, groups, isDark),
    };
  });
  if (!prepared && !measuredGroups.length) return;

  const lifecycleGeneration = lifecycleGenerationRef.current;
  mutateStreamingTextDom(() => {
    if (lifecycleGenerationRef.current !== lifecycleGeneration) return;

    const startFragment = (
      group: RevealEdgeGroupState, fragment: PreparedRevealEdgeFragment, currentTime?: CSSNumberish,
    ) => {
      const state = startRevealEdgeFragment(layer, fragment, isDark, currentTime);
      if (!state) return;

      group.fragments.push(state);
      state.animation.onfinish = () => removeRevealEdge(
        group,
        state,
        groupsRef,
        lifecycleGenerationRef,
        lifecycleGeneration,
        onSettled,
      );
    };

    measuredGroups.forEach(({ group, coloring, fragments }) => {
      if (!groupsRef.current.includes(group)) return;

      if (coloring) colorRevealEdgeGroup(group, coloring, isDark);
      if (!fragments) return;

      // A word that no longer fits its line moves to the next one, and the covers of its revealed letters go with it
      // at the point of their animation they had reached
      const currentTime = group.fragments[0]?.animation.currentTime ?? undefined;
      clearRevealEdgeCovers(group);
      fragments.forEach((fragment) => startFragment(group, fragment, currentTime));
      if (group.fragments.length) return;

      uncolorRevealEdgeGroup(group);
      groupsRef.current.splice(groupsRef.current.indexOf(group), 1);
      onSettled();
    });

    if (!prepared) return;

    const group: RevealEdgeGroupState = {
      fragments: [],
      colorings: [],
      isDark,
      sampleIndex: 0,
      startOffset: prepared.startOffset,
      text: prepared.text,
    };
    prepared.fragments.forEach((fragment) => startFragment(group, fragment));

    if (!group.fragments.length) return;

    colorRevealEdgeGroup(group, prepared.coloring, isDark);
    groupsRef.current.push(group);
    while (
      groupsRef.current.length > MAXIMUM_REVEAL_EDGE_GROUPS
      || getRevealEdgeElementCount(groupsRef.current) > MAXIMUM_REVEAL_EDGE_ELEMENTS
    ) {
      const oldestGroup = groupsRef.current.shift()!;
      clearRevealEdgeGroup(oldestGroup);
    }
  });
}

export function clearRevealEdges(groupsRef: RefObject<RevealEdgeGroupState[]>) {
  const groups = groupsRef.current;
  groupsRef.current = [];
  groups.forEach((group) => {
    uncolorRevealEdgeGroup(group);
    group.fragments.forEach(({ animation }) => {
      animation.onfinish = undefined!;
      animation.cancel();
    });
  });

  mutateStreamingTextDom(() => {
    groups.forEach((group) => {
      group.fragments.forEach(({ coverElement }) => {
        coverElement.remove();
      });
      group.fragments = [];
    });
  });
}

// The revealed text is coloured where it stands, through the highlights of its colour, from the sample its settling has
// reached
function colorRevealEdgeGroup(group: RevealEdgeGroupState, coloring: PreparedRevealEdgeColoring[], isDark: boolean) {
  uncolorRevealEdgeGroup(group);
  group.isDark = isDark;
  group.colorings = coloring.flatMap(({
    node, startOffset, endOffset, color,
  }): RevealEdgeColoring[] => {
    const range = document.createRange();
    try {
      range.setStart(node, startOffset);
      range.setEnd(node, endOffset);
    } catch {
      return [];
    }
    const highlightNames = getStreamedTextHighlightNames(color, isDark);
    if (highlightNames) addHighlightRange(highlightNames[group.sampleIndex], range);
    return [{ range, highlightNames }];
  });
  if (!group.colorings.some(({ highlightNames }) => highlightNames)) return;

  coloredGroups.add(group);
  startColoring();
}

function uncolorRevealEdgeGroup(group: RevealEdgeGroupState) {
  group.colorings.forEach(({ range, highlightNames }) => {
    if (highlightNames) deleteHighlightRange(highlightNames[group.sampleIndex], range);
  });
  group.colorings = [];
  coloredGroups.delete(group);
}

function startColoring() {
  if (isColoring) return;

  isColoring = true;
  animate(() => {
    const isDark = getIsDarkTheme();
    coloredGroups.forEach((group) => {
      if (group.isDark !== isDark) recolorRevealEdgeGroup(group, isDark);
      advanceRevealEdgeColor(group);
    });
    isColoring = coloredGroups.size > 0;
    return isColoring;
  }, requestMeasure);
}

// The theme changed while the text settles, so its colours take the new theme's palette and the text's colour in it
function recolorRevealEdgeGroup(group: RevealEdgeGroupState, isDark: boolean) {
  group.isDark = isDark;
  group.colorings.forEach((coloring) => {
    const { range, highlightNames } = coloring;
    if (highlightNames) deleteHighlightRange(highlightNames[group.sampleIndex], range);

    const element = range.startContainer.parentElement;
    coloring.highlightNames = element
      ? getStreamedTextHighlightNames(getComputedStyle(element).color, isDark)
      : undefined;
    if (coloring.highlightNames) addHighlightRange(coloring.highlightNames[group.sampleIndex], range);
  });
}

// The colours keep time with the group's glow, which starts again where its text has moved at the point it had reached
function advanceRevealEdgeColor(group: RevealEdgeGroupState) {
  const sampleIndex = Math.min(
    LAST_SAMPLE_INDEX,
    Math.floor(getRevealEdgeGroupTime(group) / STREAMED_CHARACTER_SAMPLE_INTERVAL_MS),
  );
  if (sampleIndex === group.sampleIndex) return;

  group.colorings.forEach(({ range, highlightNames }) => {
    if (!highlightNames) return;

    deleteHighlightRange(highlightNames[group.sampleIndex], range);
    addHighlightRange(highlightNames[sampleIndex], range);
  });
  group.sampleIndex = sampleIndex;
}

function startRevealEdgeFragment(
  layer: HTMLSpanElement,
  fragment: PreparedRevealEdgeFragment,
  isDark: boolean,
  currentTime?: CSSNumberish,
): RevealEdgeFragmentState | undefined {
  const coverElement = document.createElement('span');
  const textElement = document.createElement('span');
  coverElement.className = styles.revealEdgeFragment;
  textElement.className = styles.revealEdgeText;
  coverElement.dataset.agentStreamingRevealEdgeCover = '';
  // The copy draws its text from the attribute, so the page's text, which find in page and text lookups read, holds
  // the answer once while its characters settle
  textElement.dataset.agentStreamingRevealEdgeText = fragment.text;
  coverElement.style.left = `${fragment.left}px`;
  coverElement.style.top = `${fragment.top}px`;
  coverElement.style.width = `${fragment.width}px`;
  coverElement.style.height = `${fragment.height}px`;
  coverElement.style.direction = fragment.direction;
  const { backgroundColor } = fragment;
  // Where the text cannot take its colours itself, the cover hides it and the copy over it shows the whole character
  const copyKeyframes = backgroundColor ? getStreamedCharacterCopyKeyframes(fragment.color, isDark) : undefined;
  if (backgroundColor && copyKeyframes) coverElement.style.backgroundColor = backgroundColor;
  copyRevealEdgeTypography(textElement, fragment.typography);
  coverElement.appendChild(textElement);
  layer.appendChild(coverElement);

  let animation: Animation;
  try {
    // The copy draws the glow and lasts as long as the text settles, which the group's colours keep time with
    animation = textElement.animate(
      copyKeyframes ?? getStreamedCharacterGlowKeyframes(fragment.color, isDark),
      { duration: STREAMED_CHARACTER_DURATION_MS, fill: 'forwards' },
    );
    if (currentTime !== undefined) animation.currentTime = currentTime;
  } catch {
    coverElement.remove();
    return undefined;
  }

  return {
    coverElement,
    animation,
    left: fragment.left,
    top: fragment.top,
    width: fragment.width,
    height: fragment.height,
  };
}

// The text that has just come in, its last `MAXIMUM_INITIAL_REVEAL_GRAPHEMES` graphemes at most
function getRevealEdge(previousTextContent: string, currentTextContent: string) {
  const commonPrefixLength = getCommonStringPrefixLength(previousTextContent, currentTextContent);
  if (commonPrefixLength >= currentTextContent.length) return undefined;

  const changedGraphemes = segmentGraphemes(currentTextContent.slice(commonPrefixLength));
  const text = changedGraphemes
    .slice(-MAXIMUM_INITIAL_REVEAL_GRAPHEMES)
    .join('');

  return { startOffset: currentTextContent.length - text.length, text };
}

function prepareRevealEdgeGroup(
  measurement: RevealEdgeMeasurement,
  edge: { startOffset: number; text: string },
  endOffset: number,
) {
  const visualFragments = getRevealEdgeVisualFragments(measurement.textNodes, edge.startOffset, endOffset);
  const fragments = prepareVisualFragments(measurement, visualFragments);
  if (!fragments.length) return undefined;

  const pieces = measurement.isColoredInPlace
    ? getRevealEdgeTextPieces(measurement.textNodes, edge.startOffset, endOffset)
    : [];

  return { ...edge, fragments, coloring: prepareRevealEdgeColoring(measurement, pieces) };
}

// Where the text of each group lies now: its colours where they no longer lie on it, and its covers where it moved
// while they still show. A group whose text has changed under it is relaid with no fragments, which removes it.
function measureRevealEdgeGroups(
  measurement: RevealEdgeMeasurement,
  currentTextContent: string,
  groups: RevealEdgeGroupState[],
  isDark: boolean,
): MeasuredRevealEdgeGroup[] {
  return groups.map((group) => {
    const endOffset = group.startOffset + group.text.length;
    if (currentTextContent.slice(group.startOffset, endOffset) !== group.text) {
      return { group, fragments: [] };
    }

    let coloring: PreparedRevealEdgeColoring[] | undefined;
    if (measurement.isColoredInPlace) {
      const pieces = getRevealEdgeTextPieces(measurement.textNodes, group.startOffset, endOffset);
      if (group.isDark !== isDark || !getIsSameColoring(group.colorings, pieces)) {
        coloring = prepareRevealEdgeColoring(measurement, pieces);
      }
    }
    if (!getIsRevealEdgeGroupShowing(group, measurement.isColoredInPlace)) return { group, coloring };

    const visualFragments = getRevealEdgeVisualFragments(measurement.textNodes, group.startOffset, endOffset);
    if (getIsSameLayout(group.fragments, visualFragments, measurement.containerRect)) return { group, coloring };

    return { group, coloring, fragments: prepareVisualFragments(measurement, visualFragments) };
  });
}

// The covers show their glow while their characters sharpen, and the whole characters until they settle where the text
// cannot take its colours itself. Once they show nothing, they no longer follow their text.
function getIsRevealEdgeGroupShowing(group: RevealEdgeGroupState, isColoredInPlace: boolean) {
  return !isColoredInPlace || getRevealEdgeGroupTime(group) < STREAMED_CHARACTER_GLOW_DURATION_MS;
}

function getRevealEdgeGroupTime(group: RevealEdgeGroupState) {
  const currentTime = group.fragments[0]?.animation.currentTime;
  return typeof currentTime === 'number' ? currentTime : 0;
}

// The colours still lie on the text they were given, which they leave as its text nodes are replaced or rewritten
function getIsSameColoring(colorings: RevealEdgeColoring[], pieces: RevealEdgeTextPiece[]) {
  return colorings.length === pieces.length && colorings.every(({ range }, index) => {
    const { node, startOffset, endOffset } = pieces[index];
    return range.startContainer === node
      && range.endContainer === node
      && range.startOffset === startOffset
      && range.endOffset === endOffset;
  });
}

function getIsSameLayout(
  states: RevealEdgeFragmentState[],
  fragments: RevealEdgeVisualFragment[],
  containerRect: DOMRect,
) {
  return states.length === fragments.length && states.every((state, index) => {
    const { rectangle } = fragments[index];
    return Math.abs(state.left - (rectangle.left - containerRect.left)) <= SAME_LINE_TOLERANCE_PX
      && Math.abs(state.top - (rectangle.top - containerRect.top)) <= SAME_LINE_TOLERANCE_PX
      && Math.abs(state.width - rectangle.width) <= SAME_LINE_TOLERANCE_PX
      && Math.abs(state.height - rectangle.height) <= SAME_LINE_TOLERANCE_PX;
  });
}

function prepareVisualFragments(measurement: RevealEdgeMeasurement, fragments: RevealEdgeVisualFragment[]) {
  const { containerRect, colorsByElement, isColoredInPlace } = measurement;

  return fragments.map((fragment): PreparedRevealEdgeFragment => {
    const computedStyle = getComputedStyle(fragment.sourceElement);
    colorsByElement.set(fragment.sourceElement, computedStyle.color);

    return {
      backgroundColor: isColoredInPlace ? undefined : getOpaqueBackgroundColor(fragment.sourceElement),
      color: computedStyle.color,
      direction: computedStyle.direction,
      height: fragment.rectangle.height,
      left: fragment.rectangle.left - containerRect.left,
      text: fragment.text,
      top: fragment.rectangle.top - containerRect.top,
      typography: captureRevealEdgeTypography(computedStyle),
      width: fragment.rectangle.width,
    };
  });
}

function prepareRevealEdgeColoring(
  measurement: RevealEdgeMeasurement,
  pieces: RevealEdgeTextPiece[],
): PreparedRevealEdgeColoring[] {
  const { colorsByElement } = measurement;

  return pieces.map((piece) => {
    const element = piece.node.parentElement!;
    let color = colorsByElement.get(element);
    if (color === undefined) {
      color = getComputedStyle(element).color;
      colorsByElement.set(element, color);
    }

    return { ...piece, color };
  });
}

// The content's text nodes from the one holding `fromOffset` on, each with where it starts in the content's text, read
// once for all the groups of a pass. Text in tables is left out.
function collectRevealEdgeTextNodes(content: HTMLElement, fromOffset: number) {
  const textNodes: RevealEdgeTextNode[] = [];
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
  let currentNode = walker.nextNode();
  let textOffset = 0;

  while (currentNode) {
    const textNode = currentNode as Text;
    currentNode = walker.nextNode();
    const { parentElement } = textNode;
    if (parentElement?.closest('[data-agent-answer-table]')) continue;

    const startOffset = textOffset;
    textOffset += textNode.data.length;
    if (textOffset > fromOffset && parentElement) {
      textNodes.push({ node: textNode, startOffset });
    }
  }

  return textNodes;
}

// The pieces of the text nodes that hold the content's text from `startOffset` to `endOffset`
function getRevealEdgeTextPieces(textNodes: RevealEdgeTextNode[], startOffset: number, endOffset: number) {
  const pieces: RevealEdgeTextPiece[] = [];

  for (const { node, startOffset: nodeStartOffset } of textNodes) {
    if (nodeStartOffset >= endOffset) break;

    const localStartOffset = Math.max(0, startOffset - nodeStartOffset);
    const localEndOffset = Math.min(node.data.length, endOffset - nodeStartOffset);
    if (localEndOffset > localStartOffset) {
      pieces.push({ node, startOffset: localStartOffset, endOffset: localEndOffset });
    }
  }

  return pieces;
}

function getRevealEdgeVisualFragments(textNodes: RevealEdgeTextNode[], startOffset: number, endOffset: number) {
  const fragments: RevealEdgeVisualFragment[] = [];
  const range = document.createRange();

  for (const { node: textNode, startOffset: nodeStartOffset } of textNodes) {
    if (nodeStartOffset >= endOffset) break;

    const text = textNode.data;
    if (nodeStartOffset + text.length <= startOffset) continue;

    const localStartOffset = Math.max(0, startOffset - nodeStartOffset);
    const suffix = text.slice(localStartOffset, Math.max(0, endOffset - nodeStartOffset));
    const graphemes = segmentGraphemes(suffix);
    let graphemeStartOffset = localStartOffset;

    graphemes.forEach((grapheme) => {
      const graphemeEndOffset = graphemeStartOffset + grapheme.length;
      try {
        range.setStart(textNode, graphemeStartOffset);
        range.setEnd(textNode, graphemeEndOffset);
        const rectangle = Array.from(range.getClientRects())
          .find(({ width, height }) => width > 0 && height > 0);
        if (rectangle) {
          appendRevealEdgeFragment(fragments, rectangle, grapheme, textNode.parentElement!);
        }
      } catch {
        return;
      } finally {
        graphemeStartOffset = graphemeEndOffset;
      }
    });
  }

  return fragments;
}

function appendRevealEdgeFragment(
  fragments: RevealEdgeVisualFragment[],
  rectangle: DOMRect,
  text: string,
  sourceElement: HTMLElement,
) {
  const previousFragment = fragments.at(-1);
  if (
    previousFragment
    && previousFragment.sourceElement === sourceElement
    && Math.abs(previousFragment.rectangle.top - rectangle.top) <= SAME_LINE_TOLERANCE_PX
    && Math.abs(previousFragment.rectangle.height - rectangle.height) <= SAME_LINE_TOLERANCE_PX
  ) {
    previousFragment.text += text;
    previousFragment.rectangle = combineRectangles(previousFragment.rectangle, rectangle);
    return;
  }

  fragments.push({ rectangle, text, sourceElement });
}

function combineRectangles(first: DOMRect, second: DOMRect): DOMRect {
  const left = Math.min(first.left, second.left);
  const top = Math.min(first.top, second.top);
  const right = Math.max(first.right, second.right);
  const bottom = Math.max(first.bottom, second.bottom);

  return {
    x: left,
    y: top,
    left,
    top,
    right,
    bottom,
    width: right - left,
    height: bottom - top,
    toJSON: () => ({}),
  };
}

function captureRevealEdgeTypography(computedStyle: CSSStyleDeclaration): RevealEdgeTypography {
  return {
    direction: computedStyle.direction,
    fontFamily: computedStyle.fontFamily,
    fontFeatureSettings: computedStyle.fontFeatureSettings,
    fontSize: computedStyle.fontSize,
    fontStretch: computedStyle.fontStretch,
    fontStyle: computedStyle.fontStyle,
    fontVariant: computedStyle.fontVariant,
    fontWeight: computedStyle.fontWeight,
    letterSpacing: computedStyle.letterSpacing,
    lineHeight: computedStyle.lineHeight,
    textAlign: computedStyle.textAlign,
    textDecoration: computedStyle.textDecoration,
    textTransform: computedStyle.textTransform,
    wordSpacing: computedStyle.wordSpacing,
  };
}

function copyRevealEdgeTypography(element: HTMLElement, typography: RevealEdgeTypography) {
  element.style.direction = typography.direction;
  element.style.fontFamily = typography.fontFamily;
  element.style.fontFeatureSettings = typography.fontFeatureSettings;
  element.style.fontSize = typography.fontSize;
  element.style.fontStretch = typography.fontStretch;
  element.style.fontStyle = typography.fontStyle;
  element.style.fontVariant = typography.fontVariant;
  element.style.fontWeight = typography.fontWeight;
  element.style.letterSpacing = typography.letterSpacing;
  element.style.lineHeight = typography.lineHeight;
  element.style.textAlign = typography.textAlign;
  element.style.textDecoration = typography.textDecoration;
  element.style.textTransform = typography.textTransform;
  element.style.wordSpacing = typography.wordSpacing;
}

function removeRevealEdge(
  group: RevealEdgeGroupState,
  state: RevealEdgeFragmentState,
  groupsRef: RefObject<RevealEdgeGroupState[]>,
  lifecycleGenerationRef: RefObject<number>,
  lifecycleGeneration: number,
  onSettled: NoneToVoidFunction,
) {
  mutateStreamingTextDom(() => {
    if (lifecycleGenerationRef.current !== lifecycleGeneration) return;

    const fragmentIndex = group.fragments.indexOf(state);
    if (fragmentIndex < 0) return;

    group.fragments.splice(fragmentIndex, 1);
    state.animation.onfinish = undefined!;
    state.coverElement.remove();
    if (group.fragments.length) return;

    uncolorRevealEdgeGroup(group);
    const groupIndex = groupsRef.current.indexOf(group);
    if (groupIndex >= 0) {
      groupsRef.current.splice(groupIndex, 1);
    }
    onSettled();
  });
}

function clearRevealEdgeGroup(group: RevealEdgeGroupState) {
  uncolorRevealEdgeGroup(group);
  clearRevealEdgeCovers(group);
}

function clearRevealEdgeCovers(group: RevealEdgeGroupState) {
  group.fragments.forEach(({ animation, coverElement }) => {
    animation.onfinish = undefined!;
    animation.cancel();
    coverElement.remove();
  });
  group.fragments = [];
}

function getRevealEdgeElementCount(groups: RevealEdgeGroupState[]) {
  return groups.reduce((count, group) => count + group.fragments.length * 2, 0);
}

function getCommonStringPrefixLength(first: string, second: string) {
  const maximumLength = Math.min(first.length, second.length);
  let index = 0;

  while (index < maximumLength && first[index] === second[index]) {
    index += 1;
  }

  return index;
}
