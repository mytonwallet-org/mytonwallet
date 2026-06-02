import { Address, beginCell, Cell, external, storeMessage } from '@ton/core';

import type { ApiNetwork } from '../../../types';
import type { TransactionMessage } from './types';

import { callToncenterV3 } from './other';

type MessagesResponse = {
  messages: TransactionMessage[];
};

export async function fetchExternalMessageBocByHashNormalized(options: {
  network: ApiNetwork;
  msgHashNormalized: string;
}): Promise<{ boc: string; destination: string }> {
  const { network, msgHashNormalized } = options;

  const { messages } = await callToncenterV3<MessagesResponse>(network, '/messages', {
    msg_hash: [msgHashNormalized],
  });

  const message = messages?.[0];
  if (!message?.destination) {
    throw new Error('Message not found');
  }

  const body = message.message_content?.body;
  if (!body) {
    throw new Error('Message body not found');
  }

  const dest = Address.parse(message.destination);
  const bodyCell = Cell.fromBase64(body);

  const ext = external({ to: dest, body: bodyCell });
  const boc = beginCell().store(storeMessage(ext)).endCell().toBoc().toString('base64');

  return {
    boc,
    destination: message.destination,
  };
}
