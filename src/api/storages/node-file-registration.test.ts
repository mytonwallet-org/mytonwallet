import { createStorage } from './index';

// Deliberately its own file: the factory is registered on `globalThis`, so a suite that registers it
// would mask this case for every test that ran afterwards. Each test file gets a fresh environment.
describe('node-file storage registration', () => {
  it('refuses to build a node-file storage that no host has supplied', () => {
    expect(() => createStorage({ type: 'nodeFile', path: '/tmp/unregistered-storage.json' }))
      .toThrow(/no factory is registered/);
  });
});
