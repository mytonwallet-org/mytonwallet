import { startAgentV2HostContextSync } from './agentV2/hostContextSync';
import { initAgentV2HostContext } from './initAgentV2HostContext';

jest.mock('./agentV2/hostContextSync', () => ({ startAgentV2HostContextSync: jest.fn() }));

it('starts one background subscription even when initialization is requested concurrently', async () => {
  const first = initAgentV2HostContext();
  const second = initAgentV2HostContext();

  expect(startAgentV2HostContextSync).not.toHaveBeenCalled();
  await Promise.all([first, second]);
  await initAgentV2HostContext();
  expect(startAgentV2HostContextSync).toHaveBeenCalledTimes(1);
});
