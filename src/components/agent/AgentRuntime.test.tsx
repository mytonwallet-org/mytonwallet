import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentV2Classic from '../agentV2/AgentV2Classic';
import AgentRuntime from './AgentRuntime';

jest.mock('../agentV2/AgentV2Classic', () => ({
  __esModule: true,
  default: jest.fn(() => 'agent-v2-classic'),
}));

const AgentV2ClassicMock = jest.mocked(AgentV2Classic);

let root: HTMLDivElement;

beforeEach(() => {
  root = document.createElement('div');
  document.body.appendChild(root);
  AgentV2ClassicMock.mockClear();
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

    expect(root.textContent).toBe('agent-v2-classic');
    expect(AgentV2ClassicMock).toHaveBeenCalledTimes(1);
  });
});
