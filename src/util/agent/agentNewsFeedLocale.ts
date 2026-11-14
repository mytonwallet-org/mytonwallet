import type { AgentNewsFeedLocaleV2 } from '../../api/agentV2/protocol/types';

/** The news feed's language for an app language: Russian for Russian, English for the rest */
export function getAgentNewsFeedLocale(langCode: string): AgentNewsFeedLocaleV2 {
  return langCode.startsWith('ru') ? 'ru' : 'en';
}
