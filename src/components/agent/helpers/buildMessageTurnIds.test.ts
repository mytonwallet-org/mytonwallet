import type { AgentMessage } from '../../../global/types';

import buildMessageTurnIds from './buildMessageTurnIds';

describe('buildMessageTurnIds', () => {
  it('starts a turn at each outgoing message and keeps a preceding date separator with it', () => {
    const messagesById = buildMessagesById([
      [1, false],
      [2, true],
      [3, false],
      [4, true],
      [5, false],
      [6, false],
    ]);
    const ids = ['date:1', '1', '2', '3', 'date:2', '4', '5', 'date:3', '6'];

    expect(buildMessageTurnIds(ids, messagesById)).toEqual({
      'date:1': 'date:1',
      1: 'date:1',
      2: '2',
      3: '2',
      'date:2': 'date:2',
      4: 'date:2',
      5: 'date:2',
      'date:3': 'date:2',
      6: 'date:2',
    });
  });

  it('keeps existing turn ids when a new question is appended', () => {
    const messagesById = buildMessagesById([
      [1, true],
      [2, false],
      [3, true],
      [4, false],
      [5, true],
    ]);
    const ids = ['date:1', '1', '2', '3', '4'];

    expect(buildMessageTurnIds(ids, messagesById)).toEqual(
      expect.objectContaining({ 2: 'date:1', 4: '3' }),
    );
    expect(buildMessageTurnIds([...ids, '5'], messagesById)).toEqual(
      expect.objectContaining({ 2: 'date:1', 4: '3', 5: '5' }),
    );
  });
});

function buildMessagesById(entries: [number, boolean][]) {
  return Object.fromEntries(entries.map(([id, isOutgoing]): [number, AgentMessage] => [id, {
    id,
    text: `Message ${id}`,
    isOutgoing,
    timestamp: id,
  }]));
}
