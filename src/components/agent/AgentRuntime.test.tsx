import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentV2Chats from '../agentV2/AgentV2Chats';
import AgentRuntime from './AgentRuntime';

jest.mock('../agentV2/AgentV2Chats', () => ({
  __esModule: true,
  default: jest.fn(() => 'agent-v2-chats'),
}));

const AgentV2ChatsMock = jest.mocked(AgentV2Chats);

let root: HTMLDivElement;

beforeEach(() => {
  root = document.createElement('div');
  document.body.appendChild(root);
  AgentV2ChatsMock.mockClear();
});

afterEach(() => {
  TeactDOM.render(undefined, root);
  root.remove();
});

describe('AgentRuntime', () => {
  it('lazy-loads the Agent interface', async () => {
    TeactDOM.render(<AgentRuntime isActive />, root);
    expect(root.textContent).toBe('');
    await pause(100);

    expect(root.textContent).toBe('agent-v2-chats');
    expect(AgentV2ChatsMock).toHaveBeenCalledTimes(1);
  });

  it('shows the loaded interface at once when it mounts again, as across the phone breakpoint', async () => {
    TeactDOM.render(<AgentRuntime isActive />, root);
    await pause(100);
    TeactDOM.render(undefined, root);

    TeactDOM.render(<AgentRuntime isActive />, root);
    expect(root.textContent).toBe('agent-v2-chats');
  });
});
