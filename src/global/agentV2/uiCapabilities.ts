import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2HostUiCapabilities } from '../../api/agentV2/types';

export const AGENT_V2_CLASSIC_UI_CAPABILITIES: AgentV2HostUiCapabilities = {
  supportedActions: ['send', 'receive', 'stake', 'swap', 'openDapp'],
  supportsFollowups: true,
  supportsRunActivity: true,
  supportsWalletDirectory: true,
  supportsMessageEdit: true,
  supportsRegenerate: true,
  supportsSendRecipientWithoutAsset: true,
  supportsSupportHandoff: true,
};

export function getIsAgentV2SupportEntryVisible(thread?: AgentThreadSummaryV2) {
  return Boolean(AGENT_V2_CLASSIC_UI_CAPABILITIES.supportsSupportHandoff)
    && !getIsAgentV2SupportActive(thread);
}

export function getIsAgentV2SupportActive(thread?: Pick<AgentThreadSummaryV2, 'support'>) {
  return thread?.support?.state === 'waiting' || thread?.support?.state === 'operator';
}
