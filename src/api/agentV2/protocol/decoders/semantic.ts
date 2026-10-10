import type { AgentDecodedSemanticContentV1, AgentSemanticContentV1 } from '../types';

import {
  AgentV2CompatibilityError, extensibleOneOf, integer, object, string,
} from '../wireReader';

const NOTICE_CODES = new Set(['agent_unavailable', 'content_over_budget', 'web_search_no_results']);

export function semanticContent(value: unknown, path: string): AgentDecodedSemanticContentV1 {
  const result = object(value, path);
  const schemaVersion = integer(result.schemaVersion, `${path}.schemaVersion`, 1);
  if (schemaVersion !== 1 || string(result.kind, `${path}.kind`) !== 'notice') {
    return { kind: 'clientUnsupported', schemaVersion: 1 };
  }
  try {
    const code = extensibleOneOf<AgentSemanticContentV1['code']>(result.code, NOTICE_CODES, `${path}.code`);
    return { kind: 'notice', schemaVersion: 1, code };
  } catch (error) {
    if (error instanceof AgentV2CompatibilityError) {
      return { kind: 'clientUnsupported', schemaVersion: 1 };
    }
    throw error;
  }
}
