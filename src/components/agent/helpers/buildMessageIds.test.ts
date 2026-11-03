import type { AgentMessage } from '../../../global/types';

import buildMessageIds from './buildMessageIds';

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY_START = new Date(2026, 7, 11).getTime();

describe('buildMessageIds', () => {
  it('opens a date line after a pause of more than ten minutes', () => {
    const messages = buildMessages([
      DAY_START + 9 * HOUR,
      DAY_START + 9 * HOUR + 5 * MINUTE,
      DAY_START + 9 * HOUR + 20 * MINUTE,
    ]);

    expect(buildMessageIds(messages)).toEqual(['date:1', '1', '2', 'date:3', '3']);
  });

  it('opens a date line for each day when asked to, however long the pause', () => {
    const messages = buildMessages([
      DAY_START + 9 * HOUR,
      DAY_START + 20 * HOUR,
      DAY_START + 25 * HOUR,
    ]);

    expect(buildMessageIds(messages, { hasDailyDateLines: true })).toEqual(['date:1', '1', '2', 'date:3', '3']);
  });

  it('puts the "New" line after the date line of the first unread message', () => {
    const messages = buildMessages([
      DAY_START + 9 * HOUR,
      DAY_START + 9 * HOUR + MINUTE,
      DAY_START + 12 * HOUR,
    ]);

    expect(buildMessageIds(messages, { unreadMessageId: 2 })).toEqual(['date:1', '1', 'unread:2', '2', 'date:3', '3']);
    expect(buildMessageIds(messages, { unreadMessageId: 3 })).toEqual(['date:1', '1', '2', 'date:3', 'unread:3', '3']);
  });
});

function buildMessages(timestamps: number[]) {
  return timestamps.map((timestamp, index): AgentMessage => ({
    id: index + 1,
    text: `Message ${index + 1}`,
    isOutgoing: false,
    timestamp,
  }));
}
