import type { RefObject } from '../../../lib/teact/teact';

import { MAXIMUM_INITIAL_REVEAL_GRAPHEMES } from '../../../util/agent/TextRevealController';
import segmentGraphemes from '../../../util/segmentGraphemes';
import { getOpaqueBackgroundColor } from './streamingTextColor';
import { measureStreamingTextDom, mutateStreamingTextDom } from './streamingTextDom';

import styles from '../StreamingText.module.scss';

const REVEAL_EDGE_ANIMATION_DURATION_MS = 200;
const MAXIMUM_REVEAL_EDGE_GROUPS = 24;
const MAXIMUM_REVEAL_EDGE_ELEMENTS = 48;
const SAME_LINE_TOLERANCE_PX = 0.5;

interface RevealEdgeFragmentState {
  coverElement: HTMLSpanElement;
  animation: Animation;
}

export interface RevealEdgeGroupState {
  fragments: RevealEdgeFragmentState[];
}

interface RevealEdgeVisualFragment {
  rectangle: DOMRect;
  text: string;
  sourceElement: HTMLElement;
}

interface RevealEdgeTypography {
  color: string;
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
  backgroundColor: string;
  direction: string;
  height: number;
  left: number;
  text: string;
  top: number;
  typography: RevealEdgeTypography;
  width: number;
}

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

  const preparedFragments = measureStreamingTextDom(() => prepareRevealEdgeFragments(
    container,
    content,
    previousTextContent,
    currentTextContent,
  ));
  if (!preparedFragments.length) return;

  const lifecycleGeneration = lifecycleGenerationRef.current;
  mutateStreamingTextDom(() => {
    if (lifecycleGenerationRef.current !== lifecycleGeneration) return;

    const group: RevealEdgeGroupState = { fragments: [] };
    preparedFragments.forEach((fragment) => {
      const coverElement = document.createElement('span');
      const textElement = document.createElement('span');
      coverElement.className = styles.revealEdgeFragment;
      textElement.className = styles.revealEdgeText;
      coverElement.dataset.agentStreamingRevealEdgeCover = '';
      textElement.dataset.agentStreamingRevealEdgeText = '';
      textElement.textContent = fragment.text;
      coverElement.style.left = `${fragment.left}px`;
      coverElement.style.top = `${fragment.top}px`;
      coverElement.style.width = `${fragment.width}px`;
      coverElement.style.height = `${fragment.height}px`;
      coverElement.style.backgroundColor = fragment.backgroundColor;
      coverElement.style.direction = fragment.direction;
      copyRevealEdgeTypography(textElement, fragment.typography);
      coverElement.appendChild(textElement);
      layer.appendChild(coverElement);

      let animation: Animation;
      try {
        animation = textElement.animate(
          [
            {
              offset: 0,
              opacity: 0.16,
              filter: 'blur(0.3rem)',
              transform: 'translateY(0.08rem)',
            },
            {
              offset: 0.45,
              opacity: 0.72,
              filter: 'blur(0.08rem)',
              transform: 'translateY(0.02rem)',
            },
            {
              offset: 1,
              opacity: 1,
              filter: 'blur(0)',
              transform: 'translateY(0)',
            },
          ],
          {
            duration: REVEAL_EDGE_ANIMATION_DURATION_MS,
            easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)',
            fill: 'forwards',
          },
        );
      } catch {
        coverElement.remove();
        return;
      }

      const state = { coverElement, animation };
      group.fragments.push(state);
      animation.onfinish = () => removeRevealEdge(
        group,
        state,
        groupsRef,
        lifecycleGenerationRef,
        lifecycleGeneration,
        onSettled,
      );
    });

    if (!group.fragments.length) return;

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

function prepareRevealEdgeFragments(
  container: HTMLElement,
  content: HTMLElement,
  previousTextContent: string,
  currentTextContent: string,
) {
  const commonPrefixLength = getCommonStringPrefixLength(previousTextContent, currentTextContent);
  if (commonPrefixLength >= currentTextContent.length) return [];

  const changedGraphemes = segmentGraphemes(currentTextContent.slice(commonPrefixLength));
  const edgeText = changedGraphemes
    .slice(-MAXIMUM_INITIAL_REVEAL_GRAPHEMES)
    .join('');
  const edgeStartOffset = currentTextContent.length - edgeText.length;
  const fragments = getRevealEdgeVisualFragments(content, edgeStartOffset);
  if (!fragments.length) return [];

  const containerRect = container.getBoundingClientRect();

  return fragments.reduce<PreparedRevealEdgeFragment[]>((result, fragment) => {
    const computedStyle = getComputedStyle(fragment.sourceElement);
    const backgroundColor = getOpaqueBackgroundColor(fragment.sourceElement);
    if (!backgroundColor) return result;

    result.push({
      backgroundColor,
      direction: computedStyle.direction,
      height: fragment.rectangle.height,
      left: fragment.rectangle.left - containerRect.left,
      text: fragment.text,
      top: fragment.rectangle.top - containerRect.top,
      typography: captureRevealEdgeTypography(computedStyle),
      width: fragment.rectangle.width,
    });

    return result;
  }, []);
}

function getRevealEdgeVisualFragments(content: HTMLElement, startOffset: number) {
  const fragments: RevealEdgeVisualFragment[] = [];
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  let currentNode = walker.nextNode();
  let textOffset = 0;

  while (currentNode) {
    const textNode = currentNode as Text;
    const text = textNode.data;
    const nodeStartOffset = textOffset;
    const nodeEndOffset = nodeStartOffset + text.length;
    textOffset = nodeEndOffset;
    currentNode = walker.nextNode();

    if (nodeEndOffset <= startOffset || !textNode.parentElement) continue;

    const localStartOffset = Math.max(0, startOffset - nodeStartOffset);
    const suffix = text.slice(localStartOffset);
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
          appendRevealEdgeFragment(
            fragments,
            rectangle,
            grapheme,
            textNode.parentElement!,
          );
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
    color: computedStyle.color,
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
  element.style.color = typography.color;
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

    const groupIndex = groupsRef.current.indexOf(group);
    if (groupIndex >= 0) {
      groupsRef.current.splice(groupIndex, 1);
    }
    onSettled();
  });
}

function clearRevealEdgeGroup(group: RevealEdgeGroupState) {
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
