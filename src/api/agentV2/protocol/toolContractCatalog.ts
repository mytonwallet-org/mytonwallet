import type { AgentToolName, AgentToolScope } from './types';

export interface AgentV2ToolContractMetadata {
  maxResultBytes: number;
  name: AgentToolName;
  scopes: [AgentToolScope];
  timeoutMs: number;
}

// The calls are marked pure so a build without Agent V2 can drop the catalog
export const AGENT_V2_TOOL_CONTRACTS: readonly AgentV2ToolContractMetadata[] = [
  /* @__PURE__ */ tool('wallet.data.query', 'wallet.data.read'),
  /* @__PURE__ */ tool('wallet.directory.query', 'wallet.directory.read'),
];

function tool(
  name: AgentToolName,
  scope: AgentToolScope,
): AgentV2ToolContractMetadata {
  return {
    name,
    scopes: [scope],
    maxResultBytes: name === 'wallet.directory.query'
      ? 32_768
      : 98_304,
    timeoutMs: 30_000,
  };
}
