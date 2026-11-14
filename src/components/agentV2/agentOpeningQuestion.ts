import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import { cacheWhileConnected } from '../agent/helpers/agentMotion';
import getCanAnimate from '../agent/helpers/getCanAnimate';
import {
  createSentTextPicture,
  measureSentQuestionFlight,
  SENT_QUESTION_FLIGHT_DURATION,
} from '../agent/helpers/sentQuestionFlight';
import { captureFollowupSource, measureFollowupMorph } from './agentFollowupMorph';

import styles from './AgentV2Conversation.module.scss';

/** The question as the chat it opened shows it: the chat, the question's bubble and its text */
interface OpeningQuestion {
  conversation: HTMLElement;
  bubble: HTMLElement;
  text: HTMLElement;
}

// The chat shows its question by then, while what the question came from still is the question's
const QUESTION_WAIT = 1000;
const CONVERSATION_SELECTOR = '[data-agent-conversation]';
const QUESTION_TEXT_SELECTOR = '[data-agent-question-text]';
const COMPOSER_SELECTOR = '[data-agent-composer]';

/**
 * The question typed in the field under the chat list flies out of it into the first bubble of the chat it opens, as
 * a question sent in a chat flies into its bubble, over both screens. The field's text stays where it stood until the
 * chat shows the bubble, and the flight follows the bubble as the chat comes in, stretched over the screen's transition
 * so that the question lands as the chat arrives. It reads the layout, so it is called outside a mutation phase.
 */
export function startOpeningTextFlight(input: HTMLTextAreaElement, questionText: string) {
  if (!getCanAnimate()) return;

  const layer = createOpeningLayer();
  const picture = createSentTextPicture(input, layer, true);
  if (!picture) {
    requestMutation(() => layer.remove());
    return;
  }

  playOpeningQuestion(layer, questionText, picture.element, ({ conversation, bubble, text }, onEnd) => (
    measureSentQuestionFlight(
      picture,
      bubble,
      text,
      () => findOpeningQuestion(conversation, questionText)?.bubble,
      layer,
      () => conversation.querySelector(COMPOSER_SELECTOR) ?? undefined,
      () => getFlightDuration(bubble),
      onEnd,
    )
  ));
}

/**
 * The suggestion tapped under the chat list turns into the first bubble of the chat it opens, as a follow-up turns into
 * its question, over both screens. It reads the layout, so it is called outside a mutation phase.
 */
export function startOpeningSuggestionMorph(button: HTMLElement, questionText: string) {
  const source = getCanAnimate() ? captureFollowupSource(button) : undefined;
  if (!source) return;

  const layer = createOpeningLayer();
  playOpeningQuestion(layer, questionText, undefined, ({ conversation, bubble, text }, onEnd) => (
    measureFollowupMorph(
      source, bubble, text, () => findOpeningQuestion(conversation, questionText)?.bubble, layer, onEnd,
    )
  ));
}

// A layer over every screen of the Agent, for the way of a question from one screen into another
function createOpeningLayer() {
  const layer = document.createElement('div');
  layer.className = styles.openingQuestionLayer;
  layer.setAttribute('aria-hidden', 'true');
  requestMutation(() => {
    document.body.appendChild(layer);
  });
  return layer;
}

// Waits for the chat that opens to show its question, and then starts the way into it, which the layer goes with. What
// holds the field's text in place until then goes too if the question does not come in time.
function playOpeningQuestion(
  layer: HTMLElement,
  questionText: string,
  holder: HTMLElement | undefined,
  measureMotion: (question: OpeningQuestion, onEnd: NoneToVoidFunction) => (() => NoneToVoidFunction) | undefined,
) {
  const startedAt = Date.now();
  // The chat that opens takes the place of any chat screen left in the stack, so the conversation found stays the last
  // one until it leaves the document
  const findConversation = cacheWhileConnected(findLastConversation);

  animate(() => {
    const question = findOpeningQuestion(findConversation(), questionText);
    if (!question && Date.now() - startedAt < QUESTION_WAIT) return true;

    const startMotion = question && measureMotion(question, () => layer.remove());
    requestMutation(() => {
      if (startMotion) {
        startMotion();
        return;
      }

      holder?.remove();
      layer.remove();
    });
    return false;
  }, requestMeasure);
}

// The chat that opened last
function findLastConversation() {
  const conversations = document.querySelectorAll<HTMLElement>(CONVERSATION_SELECTOR);
  return conversations.length ? conversations[conversations.length - 1] : undefined;
}

// The question as `conversation` shows it
function findOpeningQuestion(conversation: HTMLElement | undefined, questionText: string): OpeningQuestion | undefined {
  const text = Array.from(conversation?.querySelectorAll<HTMLElement>(QUESTION_TEXT_SELECTOR) ?? [])
    .find((element) => element.textContent === questionText);
  const bubble = text?.parentElement;
  return conversation && text && bubble ? { conversation, bubble, text } : undefined;
}

// The flight's time into `bubble`, stretched over the rest of the transition of the screens it lies in. None while
// one of them has yet to start, as its start, which the flight keeps to, is not known before.
function getFlightDuration(bubble: HTMLElement) {
  const remaining = getRemainingScreenMotion(bubble);
  return remaining === undefined ? undefined : Math.max(SENT_QUESTION_FLIGHT_DURATION, remaining);
}

// How much longer the screens `element` lies in go on moving, as a chat slides or fades in over the list, or none while
// a screen has yet to start moving
function getRemainingScreenMotion(element: HTMLElement) {
  let remaining = 0;
  for (let ancestor: HTMLElement | null = element; ancestor; ancestor = ancestor.parentElement) {
    for (const animation of ancestor.getAnimations()) {
      const { endTime } = animation.effect?.getComputedTiming() ?? {};
      if (typeof endTime !== 'number' || !Number.isFinite(endTime)) continue;
      if (animation.pending) return undefined;

      remaining = Math.max(remaining, endTime - (Number(animation.currentTime) || 0));
    }
  }

  return remaining;
}
