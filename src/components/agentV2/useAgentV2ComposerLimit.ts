import { useEffect, useRef, useState } from '../../lib/teact/teact';

import type { AgentUserQuotaV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2AvailabilityState, AgentV2ComposerStatus } from '../../api/agentV2/types';

import { subscribeToAgentV2Updates } from '../../util/agentV2Updates';
import { areDeepEqual } from '../../util/areDeepEqual';
import { callApi } from '../../api';
import { selectAgentV2ComposerStatus } from './agentComposerStatus';

import useForceUpdate from '../../hooks/useForceUpdate';

const AVAILABLE: AgentV2AvailabilityState = { state: 'available' };

/**
 * The limit that holds for a question typed outside a chat, as under the chat list: the Agent's capacity and the
 * user's daily quota, which the server reports once the user has allowed the Agent. A chat follows its own requests
 * as well, with `useAgentV2Messages`.
 */
export default function useAgentV2ComposerLimit(isEnabled: boolean): AgentV2ComposerStatus | undefined {
  const [availability, setAvailability] = useState(AVAILABLE);
  const [quota, setQuota] = useState<AgentUserQuotaV2>();
  const forceUpdate = useForceUpdate();

  useEffect(() => subscribeToAgentV2Updates((update) => {
    if (update.kind === 'availabilityChanged') setAvailability(update.availability);
    if (update.kind === 'userQuotaChanged') setQuota(update.quota);
  }), []);

  useEffect(() => {
    if (!isEnabled) return;

    void callApi('getAgentV2Availability');
    void callApi('getAgentV2UserQuota');
  }, [isEnabled]);

  // The status keeps its object while it says the same, so that what shows it renders again only when it changes
  const statusRef = useRef<AgentV2ComposerStatus>();
  const status = isEnabled ? selectAgentV2ComposerStatus(availability, quota) : undefined;
  if (!areDeepEqual(statusRef.current, status)) statusRef.current = status;

  // A limit lets go at its reset time, when nothing else would render the composer again
  const resetAt = statusRef.current && 'resetAt' in statusRef.current ? statusRef.current.resetAt : undefined;
  useEffect(() => {
    if (resetAt === undefined) return undefined;

    const timer = window.setTimeout(forceUpdate, Math.max(0, resetAt - Date.now()) + 1);
    return () => window.clearTimeout(timer);
  }, [forceUpdate, resetAt]);

  return statusRef.current;
}
