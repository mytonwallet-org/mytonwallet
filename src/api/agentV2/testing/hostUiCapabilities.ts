import type { AgentV2HostContextSnapshot, AgentV2HostUiCapabilities } from '../types';

export function hostUiCapabilities(
  platform: AgentV2HostContextSnapshot['platform'] = 'classic',
): AgentV2HostUiCapabilities {
  return {
    supportedActions: [
      'send', 'receive', 'stake', 'swap',
      'openDapp',
    ],
    supportsFollowups: true,
    supportsRunActivity: platform !== 'android',
    supportsWalletDirectory: platform !== 'android',
    supportsMessageEdit: platform === 'classic',
    supportsRegenerate: platform === 'classic',
    supportsSendRecipientWithoutAsset: platform !== 'android',
  };
}
