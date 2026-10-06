import { installTestExtensionPorts } from '../../tests/helpers/extensionPorts';

import { createExtensionConnector, createReverseExtensionConnector } from './PostMessageConnector';

let ports: ReturnType<typeof installTestExtensionPorts>;
beforeEach(() => {
  ports = installTestExtensionPorts();
});
afterEach(() => {
  ports.restore();
});

it('keeps the latest reverse port when an older popup disconnects', async () => {
  const reverse = createReverseExtensionConnector('popup');
  createExtensionConnector('popup');
  createExtensionConnector('popup');
  ports.pairs[0].disconnect();
  ports.pairs[1].client.onMessage.addListener((data) => {
    const { messageId } = JSON.parse(data);
    ports.pairs[1].client.postMessage(JSON.stringify({ type: 'methodResponse', messageId, response: 'live' }));
  });

  await expect(reverse.request({ name: 'ping', args: [] })).resolves.toBe('live');
});

it('rejects reverse requests after the current popup disconnects', () => {
  const reverse = createReverseExtensionConnector('popup');
  createExtensionConnector('popup');
  ports.pairs[0].disconnect();
  expect(() => reverse.request({ name: 'ping', args: [] })).toThrow('not connected');
});
