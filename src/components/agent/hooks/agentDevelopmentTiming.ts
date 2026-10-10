import { AGENT_API_URL, APP_ENV } from '../../../config';
import { callApi } from '../../../api';
import { AgentClientTrace, newClientTraceId } from '../../../api/agentV2/developmentTelemetry';

const traces = new Map<string, AgentClientTrace>();

export function agentUiTrace(id?: string): AgentClientTrace | undefined {
  if (APP_ENV !== 'development'
    || !/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]+)?\//.test(AGENT_API_URL)) return undefined;
  const traceId = id ?? newClientTraceId();
  let trace = traces.get(traceId);
  if (!trace) {
    trace = new AgentClientTrace(traceId, (events) => {
      void callApi('recordAgentV2Telemetry', events).catch(() => undefined);
    });
    traces.set(traceId, trace);
    if (traces.size > 32) traces.delete(traces.keys().next().value!);
  }
  return trace;
}
