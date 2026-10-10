import type { AgentSemanticContentV1 } from '../../api/agentV2/protocol/types';
import type { LangFn } from '../../util/langProvider';

import {
  getAgentV2ErrorText,
  getAgentV2NoticeTexts,
} from './agentV2Copy';

const lang = ((key: string, value?: unknown) => {
  const values = Array.isArray(value) ? value.join('|') : '';
  return values ? `${key}:${values}` : key;
}) as LangFn;
lang.code = 'en';

describe('Agent V2 error copy', () => {
  it('distinguishes a transport interruption from provider availability failures', () => {
    expect(getAgentV2ErrorText('network_error', lang)).toBe('$agent_connection_interrupted');
    expect(getAgentV2ErrorText('provider_timeout', lang)).toBe('$agent_capacity_limit_unknown');
    expect(getAgentV2ErrorText('provider_unavailable', lang)).toBe('$agent_capacity_limit_unknown');
  });
});

describe('Agent V2 operational notices', () => {
  it.each([
    ['agent_unavailable', '$agent_error_generic'],
    ['content_over_budget', '$agent_notice_content_over_budget'],
    ['web_search_no_results', '$agent_notice_web_search_no_results'],
  ] as const)('renders %s without invoking a writer', (code, key) => {
    const content: AgentSemanticContentV1 = { kind: 'notice', schemaVersion: 1, code };
    expect(getAgentV2NoticeTexts(content, lang)).toEqual([key]);
  });
});
