import type { AgentMessage } from '../../global/types';

import { getRegenerationRemovedIds } from './useRegenerationDissolve';

const QUESTION: AgentMessage = { id: 1, text: 'Question', isOutgoing: true, timestamp: 1 };
const ANSWER: AgentMessage = { id: 2, text: 'Answer', isOutgoing: false, timestamp: 2 };
const NEXT_QUESTION: AgentMessage = { id: 3, text: 'Next question', isOutgoing: true, timestamp: 3 };
const NEXT_ANSWER: AgentMessage = { id: 4, text: 'Next answer', isOutgoing: false, timestamp: 4 };
const NEW_ANSWER: AgentMessage = { id: 5, text: '', isOutgoing: false, isTyping: true, timestamp: 5 };

describe('getRegenerationRemovedIds', () => {
  it('takes the regenerated answer and every message after it once the list drops them', () => {
    const previous = [QUESTION, ANSWER, NEXT_QUESTION, NEXT_ANSWER];

    expect(getRegenerationRemovedIds(previous, [QUESTION], ANSWER.id)).toEqual([2, 3, 4]);
    expect(getRegenerationRemovedIds(previous, [QUESTION, ANSWER, NEXT_QUESTION], NEXT_ANSWER.id)).toEqual([4]);
  });

  it('takes them when the new answer comes with the same change', () => {
    expect(getRegenerationRemovedIds([QUESTION, ANSWER], [QUESTION, NEW_ANSWER], ANSWER.id)).toEqual([2]);
  });

  it('takes nothing while the answer is still there', () => {
    expect(getRegenerationRemovedIds([QUESTION, ANSWER], [QUESTION, ANSWER], ANSWER.id)).toBeUndefined();
    expect(getRegenerationRemovedIds([QUESTION], [QUESTION], ANSWER.id)).toBeUndefined();
  });

  it('takes nothing while a message after the answer stays, as a question queued meanwhile does', () => {
    const previous = [QUESTION, ANSWER, NEXT_QUESTION];

    expect(getRegenerationRemovedIds(previous, [QUESTION, NEXT_QUESTION], ANSWER.id)).toBeUndefined();
    expect(getRegenerationRemovedIds(previous, [QUESTION, NEW_ANSWER, NEXT_QUESTION], ANSWER.id)).toBeUndefined();
  });

  it('takes nothing when the list is replaced, as by another chat or a cleared one', () => {
    const previous = [QUESTION, ANSWER];

    expect(getRegenerationRemovedIds(previous, [], ANSWER.id)).toBeUndefined();
    expect(getRegenerationRemovedIds(previous, [NEXT_QUESTION], ANSWER.id)).toBeUndefined();
  });

  it('takes nothing for a first message, which has nothing to stay before it', () => {
    expect(getRegenerationRemovedIds([ANSWER, NEXT_QUESTION], [], ANSWER.id)).toBeUndefined();
  });
});
