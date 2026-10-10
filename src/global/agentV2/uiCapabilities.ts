import type { AgentV2HostUiCapabilities } from '../../api/agentV2/types';

export const AGENT_V2_CLASSIC_UI_CAPABILITIES: AgentV2HostUiCapabilities = {
  supportedActions: ['send', 'receive', 'stake', 'swap', 'openDapp'],
  supportsFollowups: true,
  supportsRunActivity: true,
  supportsWalletDirectory: true,
  supportsMessageEdit: true,
  supportsRegenerate: true,
  supportsSendRecipientWithoutAsset: true,
};
